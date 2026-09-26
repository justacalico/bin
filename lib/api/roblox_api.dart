import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../render/glb_parser.dart';

import '../render/avatar_assembler.dart';
import '../util/gunzip_stub.dart'
    if (dart.library.io) '../util/gunzip_io.dart';

/// Result of building an avatar from the official Roblox APIs.
class AvatarFetchResult {
  const AvatarFetchResult({
    required this.userId,
    required this.username,
    required this.model,
  });

  final int userId;
  final String username;
  final AvatarModel model;
}

class AvatarFetchException implements Exception {
  AvatarFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pieces of a user's avatar spec, straight from
/// `avatar.roblox.com/v1/users/{id}/avatar`.
class AvatarSpec {
  AvatarSpec({
    required this.avatarType,
    required this.scales,
    required this.bodyColors,
    required this.assets,
  });

  /// 'R6' or 'R15'.
  final String avatarType;

  /// height, width, depth, head, proportion, bodyType multipliers.
  final Map<String, double> scales;

  /// part name -> brick color number.
  final Map<String, int> bodyColors;

  /// Worn assets: (asset id, asset type name).
  final List<(int, String)> assets;
}

/// Talks to the public Roblox endpoints: username lookup, avatar spec, and
/// asset delivery (rbxm models, .mesh geometry, png textures).
class RobloxApi {
  RobloxApi({http.Client? client}) : client = client ?? http.Client();

  final http.Client client;

  static const _timeout = Duration(seconds: 20);

  Future<int?> lookupUserId(String username) async {
    final response = await client
        .post(
          Uri.parse('https://users.roblox.com/v1/usernames/users'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'usernames': [username],
            'excludeBannedUsers': false,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AvatarFetchException(
          'user lookup failed (HTTP ${response.statusCode})');
    }
    final data = jsonDecode(response.body)['data'] as List?;
    if (data == null || data.isEmpty) return null;
    final id = data[0]['id'];
    return id is num ? id.toInt() : null;
  }

  Future<AvatarSpec> avatarSpec(int userId) async {
    final response = await client
        .get(Uri.parse('https://avatar.roblox.com/v1/users/$userId/avatar'))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AvatarFetchException(
          'avatar lookup failed (HTTP ${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final scales = <String, double>{};
    for (final e
        in (body['scales'] as Map<String, dynamic>? ?? {}).entries) {
      scales[e.key] = (e.value as num?)?.toDouble() ?? 1.0;
    }
    final colors = <String, int>{};
    for (final e
        in (body['bodyColors'] as Map<String, dynamic>? ?? {}).entries) {
      colors[e.key] = (e.value as num?)?.toInt() ?? 0;
    }
    final assets = <(int, String)>[];
    for (final a in (body['assets'] as List? ?? [])) {
      final id = (a['id'] as num?)?.toInt();
      final type = a['assetType']?['name'] as String? ?? '';
      if (id != null) assets.add((id, type));
    }
    return AvatarSpec(
      avatarType: body['playerAvatarType'] as String? ?? 'R6',
      scales: scales,
      bodyColors: colors,
      assets: assets,
    );
  }

  /// Raw bytes of an asset: rbxm model, .mesh geometry or png/jpg image.
  Future<Uint8List> asset(int id) async {
    final response = await client
        .get(Uri.parse('https://assetdelivery.roblox.com/v1/asset?id=$id'))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw AvatarFetchException(
          'asset $id download failed (HTTP ${response.statusCode})');
    }
    // some rbxm payloads arrive as gzip-wrapped files
    return gunzip(response.bodyBytes);
  }

  /// Full pipeline: username -> user id -> spec -> assembled model.
  Future<AvatarFetchResult> fetchAvatar(
    String username, {
    void Function(String status)? onStatus,
    AvatarAssembler? assembler,
  }) async {
    onStatus?.call('Resolving $username...');
    final userId = await lookupUserId(username);
    if (userId == null) {
      throw AvatarFetchException('No Roblox user named "$username"');
    }

    onStatus?.call('Fetching avatar...');
    final spec = await avatarSpec(userId);

    onStatus?.call('Building avatar...');
    final model =
        await (assembler ?? AvatarAssembler(asset)).build(spec);

    return AvatarFetchResult(
      userId: userId,
      username: username,
      model: model,
    );
  }
}
