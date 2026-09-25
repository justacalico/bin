import 'dart:typed_data';

import 'package:bin/api/action_ids.dart';
import 'package:bin/api/roblox_api.dart';
import 'package:bin/api/server_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StubIds extends ActionIds {
  _StubIds(this.ids)
      : super(
            client: MockClient((request) async => http.Response('', 404)),
            pageUrl: Uri.parse('https://example.test'));

  final Map<String, String> ids;

  @override
  Future<Map<String, String>> resolve() async => ids;
}

RobloxApi _api(Future<http.Response> Function(http.BaseRequest) handler,
    {Map<String, String>? ids}) {
  final client = MockClient(handler);
  return RobloxApi(
    client: client,
    actions: ServerActionClient(client: client),
    actionIds: _StubIds(ids ?? ActionIds.fallback),
  );
}

String _actionIdOf(http.BaseRequest request) =>
    request.headers['Next-Action'] ?? '';

void main() {
  test('exception toString', () {
    expect(AvatarFetchException('nope').toString(), 'nope');
  });

  group('lookupUserId', () {
    test('returns id on success', () async {
      final api = _api((request) async => http.Response('0:x\n1:156', 200));
      expect(await api.lookupUserId('builderman'), 156);
    });

    test('returns null for unknown user', () async {
      final api = _api((request) async => http.Response('0:x\n1:null', 200));
      expect(await api.lookupUserId('nobody_xyz'), isNull);
    });

    test('returns null for non-numeric value', () async {
      final api =
          _api((request) async => http.Response('0:x\n1:"huh"', 200));
      expect(await api.lookupUserId('nobody'), isNull);
    });
  });

  group('bakedGlbUrl', () {
    test('parses url', () async {
      final api = _api((request) async =>
          http.Response('0:x\n1:"https://cdn.test/a.glb"', 200));
      expect((await api.bakedGlbUrl(1)).toString(), 'https://cdn.test/a.glb');
    });

    test('null when not baked', () async {
      final api = _api((request) async => http.Response('0:x\n1:null', 200));
      expect(await api.bakedGlbUrl(1), isNull);
    });
  });

  group('bakeAvatar', () {
    test('ok response carries url', () async {
      final api = _api((request) async => http.Response(
          '0:x\n1:{"ok":true,"url":"https://cdn.test/b.glb"}', 200));
      final bake = await api.bakeAvatar(1);
      expect(bake.ok, isTrue);
      expect(bake.url.toString(), 'https://cdn.test/b.glb');
    });

    test('gate response carries gate and reset', () async {
      final api = _api((request) async => http.Response(
          '0:x\n1:{"ok":false,"gate":"sign-in","limit":1,"used":1,"resetsAt":"2030-01-01T00:00:00Z"}',
          200));
      final bake = await api.bakeAvatar(1);
      expect(bake.ok, isFalse);
      expect(bake.gate, 'sign-in');
      expect(bake.resetsAt, contains('2030'));
    });

    test('non-object value gives not-ok', () async {
      final api = _api((request) async => http.Response('0:x\n1:null', 200));
      expect((await api.bakeAvatar(1)).ok, isFalse);
    });
  });

  group('downloadGlb', () {
    test('returns bytes', () async {
      final api = _api((request) async =>
          http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200));
      expect(await api.downloadGlb(Uri.parse('https://cdn.test/a')),
          [1, 2, 3]);
    });

    test('throws on failure', () async {
      final api = _api((request) async => http.Response('', 404));
      expect(() => api.downloadGlb(Uri.parse('https://cdn.test/a')),
          throwsA(isA<AvatarFetchException>()));
    });
  });

  group('fetchAvatar', () {
    test('baked fast path', () async {
      final statuses = <String>[];
      final api = _api((request) async {
        final action = _actionIdOf(request);
        if (action == ActionIds.fallback[ActionIds.lookupUser]) {
          return http.Response('0:x\n1:156', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarIfBaked]) {
          return http.Response('0:x\n1:"https://cdn.test/ava.glb"', 200);
        }
        return http.Response.bytes(Uint8List.fromList([9, 9]), 200);
      });
      final result =
          await api.fetchAvatar('builderman', onStatus: statuses.add);
      expect(result.userId, 156);
      expect(result.glb, [9, 9]);
      expect(statuses.any((s) => s.contains('Resolving')), isTrue);
      expect(statuses.any((s) => s.contains('Downloading')), isTrue);
    });

    test('bake path when not baked', () async {
      final api = _api((request) async {
        final action = _actionIdOf(request);
        if (action == ActionIds.fallback[ActionIds.lookupUser]) {
          return http.Response('0:x\n1:77', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarIfBaked]) {
          return http.Response('0:x\n1:null', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarBake]) {
          return http.Response(
              '0:x\n1:{"ok":true,"url":"https://cdn.test/fresh.glb"}', 200);
        }
        return http.Response.bytes(Uint8List.fromList([5]), 200);
      });
      final statuses = <String>[];
      final result = await api.fetchAvatar('someuser', onStatus: statuses.add);
      expect(result.glb, [5]);
      expect(statuses.any((s) => s.contains('bake')), isTrue);
    });

    test('unknown user throws', () async {
      final api = _api((request) async => http.Response('0:x\n1:null', 200));
      expect(() => api.fetchAvatar('ghost'),
          throwsA(isA<AvatarFetchException>()));
    });

    test('sign-in gate produces friendly error', () async {
      final api = _api((request) async {
        final action = _actionIdOf(request);
        if (action == ActionIds.fallback[ActionIds.lookupUser]) {
          return http.Response('0:x\n1:88', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarIfBaked]) {
          return http.Response('0:x\n1:null', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarBake]) {
          return http.Response('0:x\n1:{"ok":false,"gate":"sign-in"}', 200);
        }
        return http.Response('x', 500);
      });
      expect(
        () => api.fetchAvatar('someuser'),
        throwsA(isA<AvatarFetchException>().having(
            (e) => e.message, 'message', contains('quota'))),
      );
    });

    test('bake failure without gate produces generic error', () async {
      final api = _api((request) async {
        final action = _actionIdOf(request);
        if (action == ActionIds.fallback[ActionIds.lookupUser]) {
          return http.Response('0:x\n1:88', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarIfBaked]) {
          return http.Response('0:x\n1:null', 200);
        }
        if (action == ActionIds.fallback[ActionIds.avatarBake]) {
          return http.Response('0:x\n1:{"ok":false}', 200);
        }
        return http.Response('x', 500);
      });
      expect(
        () => api.fetchAvatar('someuser'),
        throwsA(isA<AvatarFetchException>().having(
            (e) => e.message, 'message', contains('bake failed'))),
      );
    });
  });
}
