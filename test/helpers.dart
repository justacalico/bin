import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/render/glb_parser.dart';
import 'package:bin/render/math3d.dart';
import 'package:flutter/material.dart' show Color;

/// Small valid PNG (2x2 RGBA-ish RGB), reused across tests.
Uint8List testPng() => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP4z8DwHwyBNBAw/AcAR8oI+ItOQ4UAAAAASUVORK5CYII=',
    );

class GlbBin {
  final BytesBuilder data = BytesBuilder();
  final List<Map<String, dynamic>> views = [];
  final List<Map<String, dynamic>> accessors = [];

  int addView(List<int> bytes) {
    final offset = data.length;
    data.add(bytes);
    while (data.length % 4 != 0) {
      data.add([0]);
    }
    views.add({'buffer': 0, 'byteOffset': offset, 'byteLength': bytes.length});
    return views.length - 1;
  }

  int addAccessor(int view, int count, int componentType, String type,
      {bool normalized = false}) {
    accessors.add({
      'bufferView': view,
      'count': count,
      'componentType': componentType,
      'type': type,
      if (normalized) 'normalized': true,
    });
    return accessors.length - 1;
  }

  int addAccessorNoView(int count, int componentType, String type) {
    accessors.add(
        {'count': count, 'componentType': componentType, 'type': type});
    return accessors.length - 1;
  }
}

/// Builds a .glb binary from a glTF JSON map + raw bin chunk bytes.
Uint8List wrapGlb(Map<String, dynamic> gltf, Uint8List binData) {
  var json = utf8.encode(jsonEncode(gltf));
  final pad = (4 - json.length % 4) % 4;
  json = Uint8List.fromList([...json, ...List.filled(pad, 0x20)]);
  final total = 12 + 8 + json.length + 8 + binData.length;
  final out = BytesBuilder();
  void u32(int v) => out.add(Uint8List(4)
    ..buffer.asByteData().setUint32(0, v, Endian.little));
  u32(0x46546C67);
  u32(2);
  u32(total);
  u32(json.length);
  u32(0x4E4F534A);
  out.add(json);
  u32(binData.length);
  u32(0x004E4942);
  out.add(binData);
  return out.toBytes();
}

Float32List f32(List<double> values) => Float32List.fromList(values);

Uint16List u16(List<int> values) => Uint16List.fromList(values);

Uint32List u32list(List<int> values) => Uint32List.fromList(values);

/// Minimal valid glTF: two meshes (textured cube, colored cube) with node
/// transforms, plus decoy primitives to exercise skip paths.
Map<String, dynamic> baseGltf(GlbBin bin) {
  // cube: 8 verts
  const v = [
    -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0,
    1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0,
  ];
  final pv = bin.addView(f32(v).buffer.asUint8List());
  final pa = bin.addAccessor(pv, 8, 5126, 'VEC3');
  // uv stored as normalized ushort
  final uvv = bin.addView(u16([0, 0, 65535, 0, 0, 65535, 65535, 65535,
    0, 0, 65535, 0, 0, 65535, 65535, 65535]).buffer.asUint8List());
  final ua = bin.addAccessor(uvv, 8, 5123, 'VEC2', normalized: true);
  // vec4 texcoord variant for the second mesh
  final uv4v = bin.addView(
      f32(List.filled(32, 0.5)).buffer.asUint8List());
  final ua4 = bin.addAccessor(uv4v, 8, 5126, 'VEC4');
  // mat4-typed positions for the second mesh: xyz in the first 3 slots
  final pv4 = bin.addView(f32([
    for (var i = 0; i < 8; i++) ...[
      const [
        -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0,
        1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0,
      ][i * 3],
      const [
        -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0,
        1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0,
      ][i * 3 + 1],
      const [
        -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0,
        1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0,
      ][i * 3 + 2],
      ...List.filled(13, 0.0),
    ],
  ]).buffer.asUint8List());
  final paMat4 = bin.addAccessor(pv4, 8, 5126, 'MAT4');
  // indices as ushort, then uint for second mesh
  const idx = [
    0, 1, 2, 1, 3, 2, 4, 6, 5, 6, 7, 5, 0, 4, 1, 1, 4, 5,
    2, 3, 6, 3, 7, 6, 0, 2, 4, 2, 6, 4, 1, 5, 3, 3, 5, 7,
  ];
  final iv = bin.addView(u16(idx).buffer.asUint8List());
  final ia = bin.addAccessor(iv, idx.length, 5123, 'SCALAR');
  final iv32 = bin.addView(u32list(idx).buffer.asUint8List());
  final ia32 = bin.addAccessor(iv32, idx.length, 5125, 'SCALAR');
  // int16-normalized uvs for the unindexed primitive
  final uv16v = bin.addView(
      u16(List.filled(16, 16384)).buffer.asUint8List());
  final ua16 = bin.addAccessor(uv16v, 8, 5122, 'VEC2', normalized: true);
  final pngv = bin.addView(testPng());

  return {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0, 1, 99]
      }
    ],
    'nodes': [
      {
        'mesh': 0,
        'translation': [0, 0, 0],
        'name': 'Torso',
        'children': [2]
      },
      {
        'mesh': 1,
        'translation': [0, 2.5, 0],
        'scale': [0.5, 0.5, 0.5],
        'rotation': [0, 0.7071068, 0, 0.7071068],
        'name': 'Head'
      },
      {
        'matrix': [
          1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
        ],
        'name': 'Empty'
      },
      {
        'mesh': 2,
        'name': 'Lines'
      },
      {'mesh': 99, 'name': 'BadMesh'}
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': pa, 'TEXCOORD_0': ua},
            'indices': ia,
            'material': 0
          },
          {
            'attributes': {'TEXCOORD_0': ua},
            'indices': ia,
            'material': 0
          }
        ]
      },
      {
        'primitives': [
          {
            'attributes': {'POSITION': paMat4, 'TEXCOORD_0': ua4},
            'indices': ia32,
            'material': 1
          },
          {
            'attributes': {'POSITION': pa},
            'material': 2,
            'mode': 1
          },
          {
            'attributes': {'POSITION': pa, 'TEXCOORD_0': ua16},
            'material': 3
          }
        ]
      },
      {
        'primitives': [
          {
            'attributes': {'POSITION': pa},
            'indices': ia,
            'mode': 1
          }
        ]
      }
    ],
    'materials': [
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 0}
        }
      },
      {
        'pbrMetallicRoughness': {
          'baseColorFactor': [0.2, 0.8, 0.2, 1.0]
        }
      },
      {},
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 1},
          'baseColorFactor': [1, 0, 0, 1]
        }
      },
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 9}
        }
      }
    ],
    'textures': [
      {'source': 0},
      {'source': 1},
    ],
    'images': [
      {'bufferView': pngv, 'mimeType': 'image/png'},
      {'uri': 'data:image/png;base64,${base64Encode(testPng())}'},
      {'bufferView': 99},
    ],
    'bufferViews': bin.views,
    'accessors': bin.accessors,
    'buffers': [
      {'byteLength': bin.data.length}
    ],
  };
}

Uint8List buildTestGlb() {
  final bin = GlbBin();
  final gltf = baseGltf(bin);
  return wrapGlb(gltf, bin.data.toBytes());
}

/// Minimal model for tests that don't need a real GLB.
AvatarModel buildTestModel() {
  final v = <MeshVertex>[
    const MeshVertex(0, 0, 0, 0, 0),
    const MeshVertex(1, 0, 0, 1, 0),
    const MeshVertex(0.5, 1, 0, 0.5, 1),
  ];
  return AvatarModel(
    parts: [
      MeshPart(vertices: v, indices: [0, 1, 2], material: 0),
    ],
    materials: [AvatarMaterial(color: const Color(0xFF888888))],
    center: const Vec3(0.5, 0.5, 0),
    radius: 1,
    minY: 0,
  );
}

// ---- binary rbxm fixture builders ----

Uint8List rbxStr(String s) {
  final b = ascii.encode(s);
  final out = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, b.length, Endian.little)).buffer.asUint8List())
    ..add(b);
  return out.toBytes();
}

Uint8List rbxIlU32(List<int> values) {
  // byte-interleaved, most-significant byte first
  final out = BytesBuilder();
  for (var b = 3; b >= 0; b--) {
    for (final v in values) {
      out.add([(v >> (b * 8)) & 0xFF]);
    }
  }
  return out.toBytes();
}

Uint8List rbxIlI32(List<int> values) {
  final zz = values.map((v) => ((v << 1) ^ (v >> 31)) & 0xFFFFFFFF).toList();
  return rbxIlU32(zz);
}

Uint8List rbxIlI64(List<int> values) {
  final zz = values.map((v) => ((v << 1) ^ (v >> 63)) & 0xFFFFFFFFFFFFFFFF).toList();
  final out = BytesBuilder();
  for (var b = 7; b >= 0; b--) {
    for (final v in zz) {
      out.add([(v >> (b * 8)) & 0xFF]);
    }
  }
  return out.toBytes();
}

Uint8List rbxIlF32(List<double> values) {
  // rotate the bits left by one, then byte-interleave big-endian
  final rot = values.map((v) {
    final bits = (ByteData(4)..setFloat32(0, v, Endian.little))
        .getUint32(0, Endian.little);
    return ((bits << 1) | (bits >> 31)) & 0xFFFFFFFF;
  }).toList();
  return rbxIlU32(rot);
}

/// Wrap a body in a literal-only LZ4 block so chunks can exercise the
/// compressed path.
Uint8List rbxLz4Raw(Uint8List body) {
  final out = BytesBuilder();
  if (body.length < 15) {
    out.add([body.length << 4]);
    out.add(body);
    return out.toBytes();
  }
  out.add([0xF0]);
  var rem = body.length - 15;
  while (rem >= 255) {
    out.add([255]);
    rem -= 255;
  }
  out.add([rem]);
  out.add(body);
  return out.toBytes();
}

Uint8List rbxChunk(String name, Uint8List body, {bool compress = false}) {
  final n = ascii.encode(name.padRight(4, ' '));
  final payload = compress ? rbxLz4Raw(body) : body;
  final out = BytesBuilder()
    ..add(n.sublist(0, 4))
    ..add((ByteData(12)
          ..setUint32(0, compress ? payload.length : 0, Endian.little)
          ..setUint32(4, body.length, Endian.little)
          ..setUint32(8, 0, Endian.little))
        .buffer
        .asUint8List())
    ..add(payload);
  return out.toBytes();
}

BytesBuilder rbxHeader(int types, int instances) {
  return BytesBuilder()
    ..add(ascii.encode('<roblox!'))
    ..add([0x89, 0xFF, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add((ByteData(18)
          ..setUint16(0, 0, Endian.little)
          ..setUint32(2, types, Endian.little)
          ..setUint32(6, instances, Endian.little))
        .buffer
        .asUint8List());
}

Uint8List rbxInst(int typeId, String className, List<int> refDeltas,
    {bool compress = false}) {
  final b = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, typeId, Endian.little)).buffer.asUint8List())
    ..add(rbxStr(className))
    ..add([0]) // format marker comes before the count
    ..add((ByteData(4)..setUint32(0, refDeltas.length, Endian.little))
        .buffer
        .asUint8List())
    ..add(rbxIlI32(refDeltas));
  return rbxChunk('INST', b.toBytes(), compress: compress);
}

Uint8List rbxProp(int typeId, String name, int type, Uint8List data) {
  final b = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, typeId, Endian.little)).buffer.asUint8List())
    ..add(rbxStr(name))
    ..add([type])
    ..add(data);
  return rbxChunk('PROP', b.toBytes());
}

Uint8List rbxPrnt(List<int> children, List<int> parents) {
  final b = BytesBuilder()
    ..add([0])
    ..add((ByteData(4)..setUint32(0, children.length, Endian.little))
        .buffer
        .asUint8List())
    ..add(rbxIlI32(children))
    ..add(rbxIlI32(parents));
  return rbxChunk('PRNT', b.toBytes());
}

Uint8List buildBinRbxm() {
  final out = rbxHeader(2, 2);

  // SSTR: one shared string "sharedValue"
  final sstr = BytesBuilder()
    ..add(Uint8List(4)) // version
    ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List())
    ..add(Uint8List(16))
    ..add(rbxStr('sharedValue'));
  out.add(rbxChunk('SSTR', sstr.toBytes()));

  // INST: Accessory (ref 10) and Part (ref 20); the Part chunk goes through
  // the compressed path.
  out.add(rbxInst(1, 'Accessory', [10]));
  out.add(rbxInst(2, 'Part', [20], compress: true));

  // Accessory props
  out.add(rbxProp(1, 'Name', 0x01, rbxStr('BCHardHat')));
  final cf = BytesBuilder()
    ..add([0]) // rotId 0 -> raw matrix
    ..add(() {
      final b = BytesBuilder();
      for (final f in [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]) {
        b.add((ByteData(4)..setFloat32(0, f, Endian.little)).buffer.asUint8List());
      }
      return b.toBytes();
    }())
    ..add(rbxIlF32([0.0]))
    ..add(rbxIlF32([-0.25]))
    ..add(rbxIlF32([0.15]));
  out.add(rbxProp(1, 'AttachmentPoint', 0x10, cf.toBytes()));
  // preset rotation id
  final cf2 = BytesBuilder()
    ..add([0x02])
    ..add(rbxIlF32([1.0]))
    ..add(rbxIlF32([2.0]))
    ..add(rbxIlF32([3.0]));
  out.add(rbxProp(1, 'OtherCFrame', 0x10, cf2.toBytes()));
  // unknown preset id falls back to identity
  final cf3 = BytesBuilder()
    ..add([0x77])
    ..add(rbxIlF32([0.0]))
    ..add(rbxIlF32([0.0]))
    ..add(rbxIlF32([0.0]));
  out.add(rbxProp(1, 'FallbackCFrame', 0x10, cf3.toBytes()));
  out.add(rbxProp(1, 'Shared', 0x1E, rbxIlU32([0])));
  out.add(rbxProp(1, 'Big', 0x1D, rbxIlI64([123456789])));
  out.add(rbxProp(1, 'Protected', 0x1F, rbxStr('prot')));

  // Part props
  final vec3 = BytesBuilder()
    ..add(rbxIlF32([1.0]))
    ..add(rbxIlF32([2.0]))
    ..add(rbxIlF32([3.0]));
  out.add(rbxProp(2, 'Size', 0x0E, vec3.toBytes()));
  out.add(rbxProp(2, 'Anchored', 0x02, Uint8List.fromList([1])));
  out.add(rbxProp(2, 'BrickColor', 0x0B, rbxIlU32([194])));
  out.add(rbxProp(2, 'SurfaceType', 0x11, rbxIlU32([2])));
  out.add(rbxProp(2, 'FormFactor', 0x1B, rbxIlU32([3])));
  out.add(rbxProp(2, 'Friction', 0x04, rbxIlF32([0.5])));
  out.add(rbxProp(2, 'Damage', 0x03, rbxIlI32([-7])));
  final col = BytesBuilder()
    ..add(rbxIlF32([0.5]))
    ..add(rbxIlF32([0.25]))
    ..add(rbxIlF32([0.75]));
  out.add(rbxProp(2, 'Color3uint8', 0x0C, col.toBytes()));
  final vec2 = BytesBuilder()
    ..add(rbxIlF32([4.0]))
    ..add(rbxIlF32([5.0]));
  out.add(rbxProp(2, 'Whatever2', 0x0D, vec2.toBytes()));

  // unknown prop type is skipped
  out.add(rbxProp(1, 'SomeThing', 0x77, Uint8List.fromList([1, 2, 3])));

  // PRNT: part(20) -> accessory(10), accessory(10) -> root(-1)
  out.add(rbxPrnt([20, 10], [10, -1]));

  out.add(rbxChunk('END ', Uint8List(0)));
  return out.toBytes();
}

/// Minimal binary file whose root is a MeshPart carrying mesh/texture/cframe.
Uint8List buildBinMeshPart({int meshId = 100, int texId = 200}) {
  final out = rbxHeader(1, 1);
  out.add(rbxInst(1, 'MeshPart', [10]));
  out.add(rbxProp(1, 'MeshId', 0x01, rbxStr('rbxassetid://$meshId')));
  out.add(rbxProp(1, 'TextureID', 0x01, rbxStr('rbxassetid://$texId')));
  out.add(rbxProp(1, 'Name', 0x01, rbxStr('Part')));
  final cf = BytesBuilder()
    ..add([0x02])
    ..add(rbxIlF32([0.0]))
    ..add(rbxIlF32([3.0]))
    ..add(rbxIlF32([0.0]));
  out.add(rbxProp(1, 'CFrame', 0x10, cf.toBytes()));
  out.add(rbxPrnt([10], [-1]));
  out.add(rbxChunk('END ', Uint8List(0)));
  return out.toBytes();
}


/// A mini R15-style package: named MeshParts each carrying MeshId, TextureID,
/// CFrame and named Attachment children with their own CFrames.
Uint8List buildR15Package(
  List<(String, int)> parts, {
  Map<String, Map<String, List<double>>> attachments = const {},
  bool cframes = true,
}) {
  // instances: 1 Model root + one MeshPart + one Attachment per entry
  var nextId = 1;
  final partIds = <int>[];
  final attIds = <int>[];
  final modelId = nextId++;
  for (final p in parts) {
    final pid = nextId++;
    partIds.add(pid);
    for (final _ in (attachments[p.$1] ?? {}).entries) {
      attIds.add(nextId++);
    }
  }

  final out = rbxHeader(3, nextId - 1);
  out.add(rbxInst(0, 'Model', [modelId]));
  // delta-encode referents
  List<int> deltas(List<int> refs) {
    final ds = <int>[];
    var prev = 0;
    for (final r in refs) {
      ds.add(r - prev);
      prev = r;
    }
    return ds;
  }
  out.add(rbxInst(1, 'MeshPart', deltas(partIds)));
  out.add(rbxInst(2, 'Attachment', deltas(attIds)));

  // names for all instances
  final allNames = <int, String>{};
  allNames[modelId] = 'Package';
  var ai = 0;
  for (var i = 0; i < parts.length; i++) {
    allNames[partIds[i]] = parts[i].$1;
    final atts = attachments[parts[i].$1] ?? {};
    for (final n in atts.keys) {
      allNames[attIds[ai]] = n;
      ai++;
    }
  }
  void namesProp(int typeId, List<int> ids) {
    final b = BytesBuilder();
    for (final id in ids) {
      b.add(rbxStr(allNames[id]!));
    }
    out.add(rbxProp(typeId, 'Name', 0x01, b.toBytes()));
  }
  namesProp(0, [modelId]);
  namesProp(1, partIds);
  namesProp(2, attIds);

  // MeshId per part
  final meshIds = BytesBuilder();
  for (final p in parts) {
    meshIds.add(rbxStr('rbxassetid://${p.$2}'));
  }
  out.add(rbxProp(1, 'MeshId', 0x01, meshIds.toBytes()));
  // TextureID per part
  final texIds = BytesBuilder();
  for (final _ in parts) {
    texIds.add(rbxStr('rbxassetid://200'));
  }
  out.add(rbxProp(1, 'TextureID', 0x01, texIds.toBytes()));
  // CFrame per part: preset rot id + interleaved positions
  final cf = BytesBuilder();
  for (var i = 0; i < parts.length; i++) {
    cf.add([0x02]);
  }
  if (cframes) {
    for (var axis = 0; axis < 3; axis++) {
      cf.add(rbxIlF32([for (var _ in parts) axis == 1 ? 3.0 : 0.0]));
    }
    out.add(rbxProp(1, 'CFrame', 0x10, cf.toBytes()));
  }

  // attachment CFrames: identity at origin by default
  final acf = BytesBuilder();
  for (var i = 0; i < attIds.length; i++) {
    acf.add([0x02]);
  }
  final attOffsets = attachments.values
      .expand((m) => m.values)
      .toList();
  for (var axis = 0; axis < 3; axis++) {
    acf.add(rbxIlF32([
      for (var i = 0; i < attIds.length; i++)
        i < attOffsets.length ? attOffsets[i][axis] : 0.0
    ]));
  }
  out.add(rbxProp(2, 'CFrame', 0x10, acf.toBytes()));

  // parents: parts -> model, attachments -> their part
  final children = [...partIds];
  final parents = [for (var _ in partIds) modelId];
  ai = 0;
  for (var i = 0; i < parts.length; i++) {
    final atts = attachments[parts[i].$1] ?? {};
    for (final _ in atts.keys) {
      children.add(attIds[ai]);
      parents.add(partIds[i]);
      ai++;
    }
  }
  children.add(modelId);
  parents.add(-1);
  out.add(rbxPrnt(children, parents));
  out.add(rbxChunk('END ', Uint8List(0)));
  return out.toBytes();
}

/// DynamicHead-style package: a SpecialMesh plus Vector3Value attachments.
Uint8List buildDynHeadPackage() {
  final out = rbxHeader(3, 3);
  out.add(rbxInst(0, 'Model', [1]));
  out.add(rbxInst(1, 'SpecialMesh', [2]));
  out.add(rbxInst(2, 'Vector3Value', [3]));
  final names = BytesBuilder()
    ..add(rbxStr('HeadPkg'));
  out.add(rbxProp(0, 'Name', 0x01, names.toBytes()));
  final smNames = BytesBuilder()..add(rbxStr('Mesh'));
  out.add(rbxProp(1, 'Name', 0x01, smNames.toBytes()));
  final v3Names = BytesBuilder()..add(rbxStr('NeckRigAttachment'));
  out.add(rbxProp(2, 'Name', 0x01, v3Names.toBytes()));
  out.add(rbxProp(1, 'MeshId', 0x01, rbxStr('rbxassetid://100')));
  out.add(rbxProp(1, 'TextureId', 0x01, rbxStr('rbxassetid://200')));
  final val = BytesBuilder()
    ..add(rbxIlF32([0.0]))
    ..add(rbxIlF32([-0.5]))
    ..add(rbxIlF32([0.0]));
  out.add(rbxProp(2, 'Value', 0x0E, val.toBytes()));
  out.add(rbxPrnt([2, 3, 1], [1, 1, -1]));
  out.add(rbxChunk('END ', Uint8List(0)));
  return out.toBytes();
}
