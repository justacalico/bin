import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/render/lz4.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('literal-only block', () {
    // token 0x30 = 3 literals, then the literals
    final out = lz4Decompress(Uint8List.fromList([0x30, 65, 66, 67]), 3);
    expect(ascii.decode(out), 'ABC');
  });

  test('literals plus back-reference', () {
    // litLen=2, matchLen=0(+4): 'AB' then copy 4 from offset 2 -> ABABAB
    final out =
        lz4Decompress(Uint8List.fromList([0x20, 65, 66, 2, 0]), 6);
    expect(ascii.decode(out), 'ABABAB');
  });

  test('extended literal length', () {
    // 15-literal marker + extension byte
    final src = [0xF0, 1 + 3, ...List.filled(19, 88)];
    final out = lz4Decompress(Uint8List.fromList(src), 19);
    expect(out.length, 19);
    expect(out.every((b) => b == 88), isTrue);
  });

  test('extended match length', () {
    // litLen=1 'A', matchLen=15+ext, offset 1 -> run of As
    final src = [0x1F, 65, 1, 0, 0]; // matchLen=15+0+4=19, copies A 19 times
    final out = lz4Decompress(Uint8List.fromList(src), 20);
    expect(ascii.decode(out), 'A' * 20);
  });
}
