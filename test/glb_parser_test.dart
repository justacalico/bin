import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bin/render/glb_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses meshes, transforms, materials', () async {
    final model = await GlbParser().parse(buildTestGlb());
    expect(model.parts.length, 3); // textured cube, colored cube, unindexed
    expect(model.triangleCount, greaterThan(0));
    expect(model.materials.length, 5);
    expect(model.materials[0].image, isNotNull);
    expect(model.materials[1].image, isNull);
    expect(model.materials[1].color.g, closeTo(0.8, 0.01));
    expect(model.materials[2].image, isNull); // no pbr section
    expect(model.materials[3].image, isNotNull); // data uri image
    expect(model.materials[4].image, isNull); // texture index out of range
    expect(model.radius, greaterThan(0));
    expect(model.center.y, greaterThan(0));
    // head mesh is translated up 2.5 and scaled 0.5
    final headYs = model.parts[1].vertices.map((v) => v.y);
    expect(headYs.reduce((a, b) => a > b ? a : b), closeTo(3.0, 0.01));
  });

  test('unindexed primitive gets sequential indices', () async {
    final model = await GlbParser().parse(buildTestGlb());
    final unindexed = model.parts[2];
    expect(unindexed.indices.length, unindexed.vertices.length);
    for (var i = 0; i < unindexed.indices.length; i++) {
      expect(unindexed.indices[i], i);
    }
  });

  test('throws on bad magic', () async {
    final glb = buildTestGlb();
    glb[0] = 0;
    expect(() => GlbParser().parse(glb), throwsA(isA<GlbException>()));
  });

  test('throws on tiny input', () async {
    expect(() => GlbParser().parse(Uint8List(4)),
        throwsA(isA<GlbException>()));
  });

  test('throws when chunk overruns', () async {
    final glb = buildTestGlb();
    // corrupt the JSON chunk length
    final bd = ByteData.sublistView(glb);
    bd.setUint32(12, 0xFFFFFFF, Endian.little);
    expect(() => GlbParser().parse(glb), throwsA(isA<GlbException>()));
  });

  test('throws when json missing', () async {
    final bin = Uint8List(4);
    final glb = wrapGlb({}, bin);
    // remove the json chunk marker: craft a glb with only bin
    final bd = ByteData.sublistView(glb);
    bd.setUint32(16, 0x004E4942, Endian.little); // JSON chunk -> BIN type
    expect(() => GlbParser().parse(glb), throwsA(isA<GlbException>()));
  });

  test('throws when bin missing', () async {
    final bin = _onlyJson();
    expect(() => GlbParser().parse(bin), throwsA(isA<GlbException>()));
  });

  test('throws when no meshes', () async {
    final glb = wrapGlb(
      {
        'asset': {'version': '2.0'},
        'scenes': [
          {'nodes': <int>[]}
        ],
        'nodes': <Map<String, dynamic>>[],
      },
      Uint8List(4),
    );
    expect(() => GlbParser().parse(glb), throwsA(isA<GlbException>()));
  });

  test('falls back to all nodes when scene missing', () async {
    final bin = GlbBin();
    final gltf = baseGltf(bin);
    gltf.remove('scenes');
    gltf['scene'] = 3; // out of range anyway
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.parts, isNotEmpty);
  });

  test('texture source out of range gives null image', () async {
    final bin = GlbBin();
    final gltf = baseGltf(bin);
    (gltf['materials'] as List).add({
      'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 2}
      }
    });
    (gltf['textures'] as List).add({'source': 99});
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.materials.last.image, isNull);
  });

  test('image bufferView out of range gives null image', () async {
    final bin = GlbBin();
    final gltf = baseGltf(bin);
    (gltf['materials'] as List).add({
      'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 3}
      }
    });
    (gltf['textures'] as List).add({'source': 2}); // images[2]: bufferView 99
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.materials.last.image, isNull);
  });

  test('image without data gives null image', () async {
    final bin = GlbBin();
    final gltf = baseGltf(bin);
    (gltf['materials'] as List).add({
      'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 4}
      }
    });
    (gltf['textures'] as List).add({'source': 3});
    (gltf['images'] as List).add({'uri': 'https://not-data.example/x.png'});
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.materials.last.image, isNull);
  });

  test('corrupt image bytes fall back to null image', () async {
    final bin = GlbBin();
    final badv = bin.addView([1, 2, 3, 4, 5]);
    final gltf = baseGltf(bin);
    (gltf['materials'] as List).add({
      'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 5}
      }
    });
    (gltf['textures'] as List).add({'source': 4});
    (gltf['images'] as List)
        .add({'bufferView': badv, 'mimeType': 'image/png'});
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.materials.last.image, isNull);
  });

  test('empty materials list still parses', () async {
    final bin = GlbBin();
    final gltf = baseGltf(bin);
    gltf['materials'] = <Map<String, dynamic>>[];
    final model = await GlbParser().parse(wrapGlb(gltf, bin.data.toBytes()));
    expect(model.materials.length, 1);
  });

  test('custom image decoder is used', () async {
    var called = 0;
    final codec = await ui.instantiateImageCodec(testPng());
    final image = (await codec.getNextFrame()).image;
    final model = await GlbParser(imageDecoder: (bytes) async {
      called++;
      return image;
    }).parse(buildTestGlb());
    expect(called, greaterThan(0));
    expect(model.materials[0].image, same(image));
  });
}

Uint8List _onlyJson() {
  final json = Uint8List.fromList('{"asset":{"version":"2.0"}}'.codeUnits);
  final pad = (4 - json.length % 4) % 4;
  final padded = Uint8List.fromList([...json, ...List.filled(pad, 0x20)]);
  final out = BytesBuilder();
  void u32(int v) => out.add(Uint8List(4)
    ..buffer.asByteData().setUint32(0, v, Endian.little));
  u32(0x46546C67);
  u32(2);
  u32(12 + 8 + padded.length);
  u32(padded.length);
  u32(0x4E4F534A);
  out.add(padded);
  return out.toBytes();
}
