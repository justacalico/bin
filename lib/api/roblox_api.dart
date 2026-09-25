import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'action_ids.dart';
import 'server_action.dart';

/// Result of resolving a username through the avatar pipeline.
class AvatarFetchResult {
  const AvatarFetchResult({
    required this.userId,
    required this.username,
    required this.glb,
  });

  final int userId;
  final String username;
  final Uint8List glb;
}

class AvatarFetchException implements Exception {
  AvatarFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ports the rbxava fetch pipeline: username -> user id -> presigned GLB URL
/// -> GLB bytes.
class RobloxApi {
  RobloxApi({
    http.Client? client,
    ServerActionClient? actions,
    ActionIds? actionIds,
  })  : client = client ?? http.Client(),
        actions = actions ?? ServerActionClient(),
        actionIds = actionIds ?? ActionIds();

  final http.Client client;
  final ServerActionClient actions;
  final ActionIds actionIds;

  Map<String, String>? _ids;

  Future<Map<String, String>> _actionIds() async {
    return _ids ??= await actionIds.resolve();
  }

  /// Resolves a Roblox username to a numeric user id, or null when the user
  /// does not exist.
  Future<int?> lookupUserId(String username) async {
    final ids = await _actionIds();
    final body =
        await actions.call(ids[ActionIds.lookupUser]!, '["$username"]');
    final value = ServerActionClient.extractValue(body);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Returns the presigned GLB URL for an already-baked avatar, or null.
  Future<Uri?> bakedGlbUrl(int userId) async {
    final ids = await _actionIds();
    final body =
        await actions.call(ids[ActionIds.avatarIfBaked]!, '[$userId]');
    final value = ServerActionClient.extractValue(body);
    if (value is String && value.isNotEmpty) return Uri.tryParse(value);
    return null;
  }

  /// Asks the backend to bake the avatar and return its GLB URL. The backend
  /// rate limits anonymous bakes; when the quota is gone this returns a
  /// [BakeResponse] with `ok == false` and a gate/limit payload.
  Future<BakeResponse> bakeAvatar(int userId) async {
    final ids = await _actionIds();
    final body = await actions.call(ids[ActionIds.avatarBake]!, '[$userId]');
    final value = ServerActionClient.extractValue(body);
    if (value is Map<String, dynamic>) {
      return BakeResponse(
        ok: value['ok'] == true,
        url: value['url'] is String ? Uri.tryParse(value['url']) : null,
        gate: value['gate'] as String?,
        resetsAt: value['resetsAt'] as String?,
      );
    }
    return const BakeResponse(ok: false);
  }

  Future<Uint8List> downloadGlb(Uri url) async {
    final response = await client.get(url);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw AvatarFetchException(
          'avatar download failed (HTTP ${response.statusCode})');
    }
    return response.bodyBytes;
  }

  /// Full pipeline: resolve, find or bake the GLB, download it.
  /// [onStatus] receives human readable progress lines.
  Future<AvatarFetchResult> fetchAvatar(
    String username, {
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Resolving $username...');
    final userId = await lookupUserId(username);
    if (userId == null) {
      throw AvatarFetchException('No Roblox user named "$username"');
    }

    onStatus?.call('Looking up baked avatar...');
    var url = await bakedGlbUrl(userId);

    if (url == null) {
      onStatus?.call('Avatar not baked yet, requesting bake...');
      final bake = await bakeAvatar(userId);
      if (!bake.ok || bake.url == null) {
        throw AvatarFetchException(
          bake.gate == 'sign-in'
              ? 'This avatar is not baked yet and the anonymous bake quota is used up. Try again later.'
              : 'Avatar bake failed. Try again later.',
        );
      }
      url = bake.url;
    }

    onStatus?.call('Downloading model...');
    final glb = await downloadGlb(url!);
    return AvatarFetchResult(
      userId: userId,
      username: username,
      glb: glb,
    );
  }
}

class BakeResponse {
  const BakeResponse({
    required this.ok,
    this.url,
    this.gate,
    this.resetsAt,
  });

  final bool ok;
  final Uri? url;
  final String? gate;
  final String? resetsAt;
}
