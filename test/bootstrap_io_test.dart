import 'dart:io';

import 'package:bin/bootstrap_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configureProxy installs env-proxy overrides', () {
    configureProxy();
    expect(HttpOverrides.current, isNotNull);
    HttpClient().close();
  });

  test('readLocalFile reads bytes and handles missing files', () async {
    final f = File('${Directory.systemTemp.path}/bin_test_${DateTime.now().microsecondsSinceEpoch}.bin');
    await f.writeAsBytes([1, 2, 3]);
    expect(await readLocalFile(f.path), [1, 2, 3]);
    expect(await readLocalFile('${f.path}_nope'), isNull);
    await f.delete();
  });
}
