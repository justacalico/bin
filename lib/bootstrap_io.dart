import 'dart:io';
import 'dart:typed_data';

/// Routes HttpClient through the http_proxy/https_proxy environment
/// variables. dart:io ignores them by default while libcurl (used by the
/// original rbxava) honors them, so machines behind a proxy stall forever
/// without this.
void configureProxy() {
  HttpOverrides.global = _EnvProxyOverrides();
}

class _EnvProxyOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = HttpClient.findProxyFromEnvironment;
}

Future<Uint8List?> readLocalFile(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
