import 'dart:convert';
import 'dart:typed_data';

import 'glb_parser.dart' show MeshVertex;

class RbxMeshException implements Exception {
  RbxMeshException(this.message);
  final String message;
  @override
  String toString() => 'RbxMeshException: $message';
}

class RbxMesh {
  RbxMesh({required this.vertices, required this.indices});
  final List<MeshVertex> vertices;
  final List<int> indices;
}

/// Parses Roblox .mesh files (assetdelivery `asset?id=` mesh payloads):
/// text versions 1.00/1.01 and binary 2.00/3.00/4.00+.
RbxMesh parseRbxMesh(Uint8List bytes) {
  final headerEnd = bytes.indexOf(0x0A);
  if (headerEnd < 0) throw RbxMeshException('truncated mesh');
  final header = ascii.decode(bytes.sublist(0, headerEnd)).trim();
  if (!header.startsWith('version')) {
    throw RbxMeshException('bad mesh header');
  }
  final version = header.split(' ').last;
  if (version.startsWith('1.')) {
    return _parseText(bytes.sublist(headerEnd + 1), version);
  }
  return _parseBinary(bytes.sublist(headerEnd + 1), version);
}

/// `count` faces, each `[px,py,pz][nx,ny,nz][u,v,w]` x3. Some files put all 9
/// tuples on one line, others split them 3 per line — gather every tuple first.
/// v1 stores positions at double scale.
RbxMesh _parseText(Uint8List bytes, String version) {
  final s = ascii.decode(bytes, allowInvalid: true);
  final re = RegExp(r'\[([^\]]+)\]');
  final groups =
      re.allMatches(s).map((m) => m.group(1)!.split(',')).toList();
  if (groups.isEmpty) throw RbxMeshException('bad v1 mesh');
  final firstLine = s.substring(0, s.indexOf('[')).trim();
  final faceCount = int.tryParse(firstLine.split(RegExp(r'\s+')).last) ?? 0;
  if (faceCount <= 0 || groups.length < faceCount * 9) {
    throw RbxMeshException('bad v1 face count');
  }
  final scale = 0.5;
  final vertexCount = faceCount * 3;
  final vertices = <MeshVertex>[];
  final indices = List<int>.generate(vertexCount, (i) => i);
  for (var vi = 0; vi < vertexCount; vi++) {
    final p = groups[vi * 3];
    final t = groups[vi * 3 + 2];
    vertices.add(MeshVertex(
      double.parse(p[0]) * scale,
      double.parse(p[1]) * scale,
      double.parse(p[2]) * scale,
      double.parse(t[0]),
      1 - double.parse(t[1]),
    ));
  }
  return RbxMesh(vertices: vertices, indices: indices);
}

/// Binary 2.00+: u16 headerSize, u8 vertexSize, u8 faceSize, u32 numVerts,
/// u32 numFaces; vertex records of vertexSize bytes each (pos 3f, normal 3f,
/// uv 2f first, rest ignored); face records are 3 u32 indices. v3/v4 add a
/// 24-byte header with lod/bone counts and skinning data on each vertex.
RbxMesh _parseBinary(Uint8List bytes, String version) {
  if (bytes.length < 12) throw RbxMeshException('truncated binary mesh');
  final view = ByteData.sublistView(bytes);
  final major = int.tryParse(version.split('.').first) ?? 0;
  final int vertexSize;
  final int faceSize;
  final int vertexCount;
  final int faceCount;
  final int dataStart;
  int skinBytes = 0;
  if (major >= 3) {
    // u16 headerSize, u16 lodType, u32 verts, u32 faces, u16 lods,
    // u16 bones, u32 namesLen, u16 subsets, u8 flags, u8 unused
    final headerSize = view.getUint16(0, Endian.little);
    vertexCount = view.getUint32(4, Endian.little);
    faceCount = view.getUint32(8, Endian.little);
    final bones = view.getUint16(14, Endian.little);
    vertexSize = 40;
    // skinned meshes carry 8 bytes of weights/bone ids per vertex in a
    // separate block between the vertex and face data
    if (bones > 0) skinBytes = vertexCount * 8;
    faceSize = 12;
    dataStart = headerSize;
  } else {
    vertexSize = view.getUint8(2);
    faceSize = view.getUint8(3);
    vertexCount = view.getUint32(4, Endian.little);
    faceCount = view.getUint32(8, Endian.little);
    dataStart = 12;
  }
  if (vertexCount <= 0 || faceCount <= 0 || vertexSize < 32) {
    throw RbxMeshException('bad binary mesh header');
  }
  final vertices = <MeshVertex>[];
  var off = dataStart;
  for (var i = 0; i < vertexCount; i++) {
    if (off + 32 > bytes.length) throw RbxMeshException('truncated vertex data');
    var px = view.getFloat32(off, Endian.little);
    var py = view.getFloat32(off + 4, Endian.little);
    var pz = view.getFloat32(off + 8, Endian.little);
    var u = view.getFloat32(off + 24, Endian.little);
    var v = view.getFloat32(off + 28, Endian.little);
    // dead vertex slots carry NaN/Inf/absurd garbage; faces never use them
    bool bad(double x) => !x.isFinite || x.abs() > 1e6;
    if (bad(px) || bad(py) || bad(pz)) {
      px = py = pz = 0;
    }
    if (bad(u)) u = 0;
    if (bad(v)) v = 0;
    vertices.add(MeshVertex(px, py, pz, u, v));
    off += vertexSize;
  }
  off += skinBytes;
  final indices = <int>[];
  final faceBytes = faceSize >= 12 ? 12 : faceSize;
  for (var i = 0; i < faceCount; i++) {
    if (off + faceBytes > bytes.length) {
      throw RbxMeshException('truncated face data');
    }
    for (var j = 0; j < 3; j++) {
      indices.add(view.getUint32(off + j * 4, Endian.little));
    }
    off += faceSize;
  }
  return RbxMesh(vertices: vertices, indices: indices);
}
