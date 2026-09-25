import 'dart:convert';

import 'package:bin/api/server_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('exception toString', () {
    expect(ServerActionException('oops').toString(),
        'ServerActionException: oops');
  });

  group('ServerActionClient.call', () {
    test('posts payload with action headers and returns body', () async {
      String? seenBody;
      Map<String, String>? seenHeaders;
      final client = ServerActionClient(
        client: MockClient((request) async {
          seenBody = request.body;
          seenHeaders = request.headers;
          return http.Response('1:"ok"', 200);
        }),
      );
      final body = await client.call('abc123', '["roblox"]');
      expect(body, '1:"ok"');
      expect(seenBody, '["roblox"]');
      expect(seenHeaders?['Next-Action'], 'abc123');
      expect(seenHeaders?['Accept'], 'text/x-component');
    });

    test('throws on non-200', () async {
      final client = ServerActionClient(
        client: MockClient((request) async => http.Response('nope', 500)),
      );
      expect(() => client.call('x', '[]'),
          throwsA(isA<ServerActionException>()));
    });
  });

  group('ServerActionClient.extractValue', () {
    test('decodes the value frame', () {
      final body = '0:{"a":"\$@1","f":"","q":"","i":false}\n1:156';
      expect(ServerActionClient.extractValue(body), 156);
    });

    test('decodes quoted string', () {
      expect(
          ServerActionClient.extractValue('0:x\n1:"https://a/b.glb"'),
          'https://a/b.glb');
    });

    test('decodes object', () {
      final value =
          ServerActionClient.extractValue('0:x\n1:${jsonEncode({'ok': true})}');
      expect(value, isA<Map>());
      expect(value['ok'], isTrue);
    });

    test('returns null on explicit null', () {
      expect(ServerActionClient.extractValue('0:x\n1:null'), isNull);
    });

    test('throws when no value frame', () {
      expect(() => ServerActionClient.extractValue('0:{}'),
          throwsA(isA<ServerActionException>()));
    });
  });
}
