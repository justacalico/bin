import 'package:http/http.dart' as http;

/// Discovers the current Next.js server action IDs from the renderbux page.
/// The IDs change on every site deploy, so they are scraped from the page's
/// JS chunks instead of being hardcoded. Falls back to the last known IDs
/// when discovery fails.
class ActionIds {
  ActionIds({
    http.Client? client,
    Uri? pageUrl,
  })  : client = client ?? http.Client(),
        pageUrl = pageUrl ?? defaultPageUrl;

  final http.Client client;
  final Uri pageUrl;

  static final defaultPageUrl = Uri.parse('https://www.renderbux.com/p/new');

  /// Server action names the app relies on.
  static const lookupUser = 'lookupUserIdByName';
  static const avatarIfBaked = 'getUserAvatarIfBaked';
  static const avatarBake = 'getUserAvatar';
  static const required = [lookupUser, avatarIfBaked, avatarBake];

  /// Last known good values, used when the page cannot be scraped.
  static const fallback = {
    lookupUser: '7fa1298165131e8c853adde6ce76d900d061de7221',
    avatarIfBaked: '408292d42b456d2d5c44ec280096d6eb0c7b4046ab',
    avatarBake: '60d5d7f5953c15f27904907eda44dfd6d6ce5b8f7e',
  };

  static final _scriptRe = RegExp(r'src="(/_next/[^"]+\.js[^"]*)"');
  static final _refRe =
      RegExp(r'createServerReference\)\("([0-9a-f]+)"([^)]*)\)');
  static final _nameRe = RegExp(r'"([A-Za-z0-9_$]+)"');

  /// Returns action id by action name. Never throws: any failure just falls
  /// back to the bundled IDs.
  Future<Map<String, String>> resolve() async {
    final discovered = <String, String>{};
    try {
      final html = await _get(pageUrl);
      if (html != null) {
        final chunks = _scriptRe
            .allMatches(html)
            .map((m) => pageUrl.resolve(m.group(1)!))
            .toSet();
        for (final js in await Future.wait(chunks.map(_get))) {
          if (js == null) continue;
          for (final m in _refRe.allMatches(js)) {
            final id = m.group(1)!;
            final names =
                _nameRe.allMatches(m.group(2)!).map((n) => n.group(1)!).toList();
            if (names.isEmpty) continue;
            final name = names.last;
            if (required.contains(name)) {
              discovered[name] = id;
            }
          }
        }
      }
    } catch (_) {
      // fall through to bundled ids
    }
    return {...fallback, ...discovered};
  }

  Future<String?> _get(Uri url) async {
    try {
      final response = await client.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return response.body;
    } catch (_) {}
    return null;
  }
}
