import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/api/roblox_api.dart';
import 'package:bin/render/avatar_assembler.dart';
import 'package:bin/render/glb_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

RobloxApi _api(Future<http.Response> Function(http.BaseRequest) handler) =>
    RobloxApi(client: MockClient(handler));

class _FakeAssembler extends AvatarAssembler {
  _FakeAssembler(this.model) : super((_) async => Uint8List(0));
  final AvatarModel model;
  @override
  Future<AvatarModel> build(AvatarSpec spec) async => model;
}

void main() {
  test('exception toString', () {
    expect(AvatarFetchException('nope').toString(), 'nope');
  });

  group('lookupUserId', () {
    test('returns id on success', () async {
      final api = _api((r) async =>
          http.Response(jsonEncode({'data': [{'id': 156}]}), 200));
      expect(await api.lookupUserId('builderman'), 156);
    });

    test('null for unknown user', () async {
      final api = _api((r) async => http.Response('{"data":[]}', 200));
      expect(await api.lookupUserId('nobody_xyz'), isNull);
    });

    test('null for non-numeric id', () async {
      final api = _api((r) async =>
          http.Response(jsonEncode({'data': [{'id': 'x'}]}), 200));
      expect(await api.lookupUserId('x'), isNull);
    });

    test('throws on non-200', () async {
      final api = _api((r) async => http.Response('err', 500));
      expect(() => api.lookupUserId('x'),
          throwsA(isA<AvatarFetchException>()));
    });
  });

  group('avatarSpec', () {
    test('parses type, scales, colors, assets', () async {
      final api = _api((r) async => http.Response(jsonEncode({
            'playerAvatarType': 'R15',
            'scales': {'height': 1.05, 'width': 0.9},
            'bodyColors': {'headColorId': 226, 'torsoColorId': 1017},
            'assets': [
              {'id': 7, 'assetType': {'name': 'Hat'}},
              {'id': 9, 'name': 'x'},
            ],
          }), 200));
      final spec = await api.avatarSpec(1);
      expect(spec.avatarType, 'R15');
      expect(spec.scales['height'], 1.05);
      expect(spec.bodyColors['headColorId'], 226);
      expect(spec.assets, [(7, 'Hat'), (9, '')]);
    });

    test('throws on non-200', () async {
      final api = _api((r) async => http.Response('err', 404));
      expect(() => api.avatarSpec(1), throwsA(isA<AvatarFetchException>()));
    });
  });

  group('asset', () {
    test('returns bytes', () async {
      final api = _api((r) async => http.Response.bytes([1, 2, 3], 200));
      expect(await api.asset(5), [1, 2, 3]);
    });

    test('throws on failure', () async {
      final api = _api((r) async => http.Response.bytes([], 200));
      expect(() => api.asset(5), throwsA(isA<AvatarFetchException>()));
      final api2 = _api((r) async => http.Response.bytes([1], 500));
      expect(() => api2.asset(5), throwsA(isA<AvatarFetchException>()));
    });
  });

  group('fetchAvatar', () {
    test('full pipeline returns model', () async {
      var calls = 0;
      final api = _api((r) async {
        calls++;
        if (r.url.host.contains('users')) {
          return http.Response(jsonEncode({'data': [{'id': 156}]}), 200);
        }
        return http.Response(jsonEncode({
          'playerAvatarType': 'R6',
          'scales': <String, double>{},
          'bodyColors': <String, int>{},
          'assets': <dynamic>[],
        }), 200);
      });
      final statuses = <String>[];
      final result = await api.fetchAvatar('builderman',
          onStatus: statuses.add, assembler: _FakeAssembler(buildTestModel()));
      expect(result.userId, 156);
      expect(result.model.parts, isNotEmpty);
      expect(statuses, isNotEmpty);
      expect(calls, 2);
    });

    test('unknown user throws', () async {
      final api = _api((r) async => http.Response('{"data":[]}', 200));
      expect(() => api.fetchAvatar('ghost'),
          throwsA(isA<AvatarFetchException>()));
    });

    test('default assembler builds model', () async {
      final api = _api((r) async {
        if (r.url.host.contains('users')) {
          return http.Response(jsonEncode({'data': [{'id': 156}]}), 200);
        }
        return http.Response(jsonEncode({
          'playerAvatarType': 'R6',
          'scales': <String, double>{},
          'bodyColors': <String, int>{'headColorId': 26},
          'assets': <dynamic>[],
        }), 200);
      });
      final result = await api.fetchAvatar('builderman');
      expect(result.model.parts.length, greaterThan(3));
    });
  });
}
