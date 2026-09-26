import 'dart:io';
import 'dart:typed_data';

import 'package:bin/util/gunzip_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decompresses gzip payloads', () {
    final raw = gzip.encode([1, 2, 3, 4]);
    expect(gunzip(Uint8List.fromList(raw)), [1, 2, 3, 4]);
  });

  test('passes non-gzip data through', () {
    expect(gunzip(Uint8List.fromList([9, 8, 7])), [9, 8, 7]);
  });
}
