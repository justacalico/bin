import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/render/rbx_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _textMesh() {
  // version 1.00, 1 face, 3 lines of [pos][norm][uv]
  const face = '[0,2,0][0,1,0][0,0,0]'
      '[2,0,0][0,1,0][1,0,0]'
      '[0,0,2][0,1,0][0.5,1,0]';
  return ascii.encode('version 1.00\n1\n$face\n');
}

Uint8List _binaryMesh() {
  final out = BytesBuilder();
  out.add(ascii.encode('version 2.00\n'));
  out.add([12, 0, 40, 12]); // headerSize, vertexSize, faceSize
  final counts = ByteData(8)
    ..setUint32(0, 3, Endian.little)
    ..setUint32(4, 1, Endian.little);
  out.add(counts.buffer.asUint8List());
  for (var i = 0; i < 3; i++) {
    final v = ByteData(40)
      ..setFloat32(0, i.toDouble(), Endian.little)
      ..setFloat32(4, i * 2.0, Endian.little)
      ..setFloat32(8, i * 3.0, Endian.little)
      ..setFloat32(24, 0.25 * i, Endian.little)
      ..setFloat32(28, 0.5, Endian.little);
    out.add(v.buffer.asUint8List());
  }
  final face = ByteData(12)
    ..setUint32(0, 0, Endian.little)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 2, Endian.little);
  out.add(face.buffer.asUint8List());
  return out.toBytes();
}

void main() {
  test('parses v1.00 text mesh with half scale and flipped v', () {
    final m = parseRbxMesh(_textMesh());
    expect(m.vertices.length, 3);
    expect(m.vertices[0].x, 0);
    expect(m.vertices[0].y, 1); // 2 * 0.5
    expect(m.vertices[1].x, 1); // 2 * 0.5
    expect(m.vertices[2].v, 0); // 1 - 1
    expect(m.indices, [0, 1, 2]);
  });

  test('parses binary v2.00 mesh', () {
    final m = parseRbxMesh(_binaryMesh());
    expect(m.vertices.length, 3);
    expect(m.vertices[1].y, 2);
    expect(m.vertices[1].u, 0.25);
    expect(m.indices, [0, 1, 2]);
  });

  test('errors', () {
    expect(() => parseRbxMesh(Uint8List(0)), throwsA(isA<RbxMeshException>()));
    expect(() => parseRbxMesh(ascii.encode('nope\n')),
        throwsA(isA<RbxMeshException>()));
    expect(() => parseRbxMesh(ascii.encode('version 1.00\n')),
        throwsA(isA<RbxMeshException>()));
    expect(() => parseRbxMesh(ascii.encode('version 1.00\n0\n')),
        throwsA(isA<RbxMeshException>()));
    expect(() => parseRbxMesh(ascii.encode('version 1.00\n2\nnothing\n')),
        throwsA(isA<RbxMeshException>()));
    expect(() => parseRbxMesh(ascii.encode('version 2.00\n')),
        throwsA(isA<RbxMeshException>()));
    // header with zero counts
    final bad = BytesBuilder()
      ..add(ascii.encode('version 2.00\n'))
      ..add([12, 0, 40, 12])
      ..add(Uint8List(8));
    expect(() => parseRbxMesh(bad.toBytes()),
        throwsA(isA<RbxMeshException>()));
    // truncated vertex data
    final trunc = BytesBuilder()
      ..add(ascii.encode('version 2.00\n'))
      ..add([12, 0, 40, 12])
      ..add((ByteData(8)
            ..setUint32(0, 3, Endian.little)
            ..setUint32(4, 1, Endian.little))
          .buffer
          .asUint8List())
      ..add(Uint8List(10));
    expect(() => parseRbxMesh(trunc.toBytes()),
        throwsA(isA<RbxMeshException>()));
    // truncated face data
    final truncF = BytesBuilder()
      ..add(ascii.encode('version 2.00\n'))
      ..add([12, 0, 40, 12])
      ..add((ByteData(8)
            ..setUint32(0, 1, Endian.little)
            ..setUint32(4, 2, Endian.little))
          .buffer
          .asUint8List())
      ..add(Uint8List(40));
    expect(() => parseRbxMesh(truncF.toBytes()),
        throwsA(isA<RbxMeshException>()));
  });

  test('parses v4.00 skinned mesh', () {
    final out = BytesBuilder();
    out.add(ascii.encode('version 4.00\n'));
    final hdr = ByteData(24)
      ..setUint16(0, 24, Endian.little)
      ..setUint16(2, 3, Endian.little)
      ..setUint32(4, 3, Endian.little)
      ..setUint32(8, 1, Endian.little)
      ..setUint16(12, 1, Endian.little)
      ..setUint16(14, 4, Endian.little);
    out.add(hdr.buffer.asUint8List());
    for (var i = 0; i < 3; i++) {
      final v = ByteData(40)
        ..setFloat32(0, i * 2.0, Endian.little)
        ..setFloat32(4, i * 3.0, Endian.little)
        ..setFloat32(8, i.toDouble(), Endian.little)
        ..setFloat32(24, 0.1, Endian.little)
        ..setFloat32(28, 0.2, Endian.little);
      out.add(v.buffer.asUint8List());
    }
    // weights + bone ids block (8 bytes per skinned vertex)
    out.add(Uint8List(3 * 8));
    final face = ByteData(12)
      ..setUint32(0, 0, Endian.little)
      ..setUint32(4, 1, Endian.little)
      ..setUint32(8, 2, Endian.little);
    out.add(face.buffer.asUint8List());
    final m = parseRbxMesh(out.toBytes());
    expect(m.vertices.length, 3);
    expect(m.vertices[1].x, 2.0);
    expect(m.vertices[1].u, closeTo(0.1, 1e-6));
    expect(m.indices, [0, 1, 2]);
  });

  test('v1 mesh with fewer tuples than declared throws', () {
    final bytes = ascii.encode(
        'version 1.00\n5\n[0,0,0][0,0,1][0,0,0][1,0,0][0,0,1][0,0,0][0,1,0][0,0,1][0,0,0]\n');
    expect(() => parseRbxMesh(bytes), throwsA(isA<RbxMeshException>()));
  });

  test('v1 mesh with split tuple lines parses', () {
    final bytes = ascii.encode('version 1.00\n1\n'
        '[0,0,0][0,0,1][0,0,0]\n'
        '[2,0,0][0,0,1][1,0,0]\n'
        '[0,2,0][0,0,1][0,1,0]\n');
    final m = parseRbxMesh(bytes);
    expect(m.vertices.length, 3);
    expect(m.vertices[1].x, closeTo(1.0, 1e-6));
    expect(m.vertices[2].y, closeTo(1.0, 1e-6));
  });

  test('exception toString', () {
    expect(RbxMeshException('x').toString(), 'RbxMeshException: x');
  });
}
