import 'package:bin/api/action_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _chunk = '''
var t=e.i(658876);
let a=(0,t.createServerReference)("aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",t.callServer,void 0,t.findSourceMapURL,"lookupUserIdByName");
let b=(0,t.createServerReference)("bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222",t.callServer,void 0,t.findSourceMapURL,"getUserAvatarIfBaked");
let c=(0,t.createServerReference)("cccc3333cccc3333cccc3333cccc3333cccc3333",t.callServer,void 0,t.findSourceMapURL,"getUserAvatar");
let d=(0,t.createServerReference)("dddd4444dddd4444dddd4444dddd4444dddd4444",t.callServer,void 0,t.findSourceMapURL,"unrelatedAction");
''';

void main() {
  test('scrapes action ids from page chunks', () async {
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async {
        if (request.url.path == '/page') {
          return http.Response(
              '<script src="/_next/static/chunks/a.js"></script>', 200);
        }
        if (request.url.path == '/_next/static/chunks/a.js') {
          return http.Response(_chunk, 200);
        }
        return http.Response('not found', 404);
      }),
    );
    final ids = await resolver.resolve();
    expect(ids[ActionIds.lookupUser],
        'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111');
    expect(ids[ActionIds.avatarIfBaked],
        'bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222');
    expect(ids[ActionIds.avatarBake],
        'cccc3333cccc3333cccc3333cccc3333cccc3333');
    expect(ids.containsKey('unrelatedAction'), isFalse);
  });

  test('falls back when page fetch fails', () async {
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async => http.Response('err', 500)),
    );
    final ids = await resolver.resolve();
    expect(ids, ActionIds.fallback);
  });

  test('falls back when client throws', () async {
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async => throw Exception('offline')),
    );
    expect(await resolver.resolve(), ActionIds.fallback);
  });

  test('partial discovery merges over fallback', () async {
    const partial = '''
let a=(0,t.createServerReference)("aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",t.callServer,void 0,t.findSourceMapURL,"lookupUserIdByName");
''';
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async {
        if (request.url.path == '/page') {
          return http.Response(
              '<script src="/_next/a.js"></script>', 200);
        }
        return http.Response(partial, 200);
      }),
    );
    final ids = await resolver.resolve();
    expect(ids[ActionIds.lookupUser],
        'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111');
    expect(ids[ActionIds.avatarBake], ActionIds.fallback[ActionIds.avatarBake]);
  });

  test('chunk returning non-200 is skipped', () async {
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async {
        if (request.url.path == '/page') {
          return http.Response(
              '<script src="/_next/a.js"></script><script src="/_next/b.js"></script>',
              200);
        }
        if (request.url.path == '/_next/a.js') {
          return http.Response('err', 404);
        }
        return http.Response(_chunk, 200);
      }),
    );
    final ids = await resolver.resolve();
    expect(ids[ActionIds.lookupUser],
        'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111');
  });

  test('reference without name is ignored', () async {
    const weird = '''
let a=(0,t.createServerReference)("aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",);
''';
    final resolver = ActionIds(
      pageUrl: Uri.parse('https://example.test/page'),
      client: MockClient((request) async {
        if (request.url.path == '/page') {
          return http.Response('<script src="/_next/a.js"></script>', 200);
        }
        return http.Response(weird, 200);
      }),
    );
    expect(await resolver.resolve(), ActionIds.fallback);
  });
}
