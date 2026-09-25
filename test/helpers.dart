import 'dart:convert';
import 'dart:typed_data';

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
