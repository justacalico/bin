import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'math3d.dart';

class GlbException implements Exception {
  GlbException(this.message);

  final String message;

  @override
  String toString() => 'GlbException: $message';
}

class MeshVertex {
  const MeshVertex(this.x, this.y, this.z, this.u, this.v);

  final double x;
  final double y;
  final double z;
  final double u;
  final double v;
}

class MeshPart {
  MeshPart({
    required this.vertices,
    required this.indices,
    required this.material,
  });

  /// World-space positions plus UVs.
  final List<MeshVertex> vertices;
  final List<int> indices;
  final int material;
}

class AvatarMaterial {
  AvatarMaterial({required this.color, this.image});

  final Color color;
  final ui.Image? image;
}

class AvatarModel {
  AvatarModel({
    required this.parts,
    required this.materials,
    required this.center,
    required this.radius,
    required this.minY,
  });

  final List<MeshPart> parts;
  final List<AvatarMaterial> materials;
  final Vec3 center;
  final double radius;
  final double minY;

  int get triangleCount =>
      parts.fold(0, (sum, p) => sum + p.indices.length ~/ 3);
}

/// Parses a binary glTF (.glb) file into an [AvatarModel]. Only what the
/// renderer needs: positions, UVs, indices, node transforms, base color
/// materials and embedded PNG/JPEG textures.
class GlbParser {
  GlbParser({Future<ui.Image> Function(Uint8List bytes)? imageDecoder})
      : _decodeImage = imageDecoder ?? _defaultImageDecoder;

  final Future<ui.Image> Function(Uint8List bytes) _decodeImage;

  static Future<ui.Image> _defaultImageDecoder(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<AvatarModel> parse(Uint8List data) async {
    final (jsonMap, bin) = _readContainer(data);

    final bufferViews = (jsonMap['bufferViews'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final accessors = (jsonMap['accessors'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final materials = (jsonMap['materials'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final textures =
        (jsonMap['textures'] as List? ?? []).cast<Map<String, dynamic>>();
    final images =
        (jsonMap['images'] as List? ?? []).cast<Map<String, dynamic>>();
    final meshes =
        (jsonMap['meshes'] as List? ?? []).cast<Map<String, dynamic>>();
    final nodes =
        (jsonMap['nodes'] as List? ?? []).cast<Map<String, dynamic>>();

    final parts = <MeshPart>[];
    _walkScene(jsonMap, nodes, meshes, accessors, bufferViews, bin, parts);
    if (parts.isEmpty) {
      throw GlbException('no meshes in glb');
    }

    var min = const Vec3(double.infinity, double.infinity, double.infinity);
    var max = min * -1;
    for (final part in parts) {
      for (final v in part.vertices) {
        min = Vec3(
          v.x < min.x ? v.x : min.x,
          v.y < min.y ? v.y : min.y,
          v.z < min.z ? v.z : min.z,
        );
        max = Vec3(
          v.x > max.x ? v.x : max.x,
          v.y > max.y ? v.y : max.y,
          v.z > max.z ? v.z : max.z,
        );
      }
    }
    final center = Vec3(
      (min.x + max.x) / 2,
      (min.y + max.y) / 2,
      (min.z + max.z) / 2,
    );
    var radius = 0.0;
    for (final part in parts) {
      for (final v in part.vertices) {
        final d = (Vec3(v.x, v.y, v.z) - center).length;
        if (d > radius) radius = d;
      }
    }
    if (radius == 0) radius = 1;

    final decodedMaterials = <AvatarMaterial>[];
    for (final mat in materials) {
      decodedMaterials.add(
        await _decodeMaterial(mat, textures, images, bufferViews, bin),
      );
    }
    if (decodedMaterials.isEmpty) {
      decodedMaterials.add(AvatarMaterial(color: const Color(0xFFB0B0B0)));
    }

    return AvatarModel(
      parts: parts,
      materials: decodedMaterials,
      center: center,
      radius: radius,
      minY: min.y,
    );
  }

  (Map<String, dynamic>, ByteData) _readContainer(Uint8List data) {
    if (data.length < 12) throw GlbException('file too small');
    final view = ByteData.sublistView(data);
    if (view.getUint32(0, Endian.little) != 0x46546C67) {
      throw GlbException('bad magic');
    }
    Map<String, dynamic>? jsonMap;
    ByteData? bin;
    var offset = 12;
    while (offset + 8 <= data.length) {
      final chunkLength = view.getUint32(offset, Endian.little);
      final chunkType = view.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + chunkLength > data.length) {
        throw GlbException('chunk overruns file');
      }
      final bytes = Uint8List.sublistView(data, start, start + chunkLength);
      if (chunkType == 0x4E4F534A) {
        jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } else if (chunkType == 0x004E4942) {
        bin = ByteData.sublistView(bytes);
      }
      offset = start + chunkLength;
    }
    if (jsonMap == null) throw GlbException('missing JSON chunk');
    if (bin == null) throw GlbException('missing BIN chunk');
    return (jsonMap, bin);
  }

  void _walkScene(
    Map<String, dynamic> gltf,
    List<Map<String, dynamic>> nodes,
    List<Map<String, dynamic>> meshes,
    List<Map<String, dynamic>> accessors,
    List<Map<String, dynamic>> bufferViews,
    ByteData bin,
    List<MeshPart> out,
  ) {
    final sceneIndex = gltf['scene'] as int? ?? 0;
    final scenes =
        (gltf['scenes'] as List? ?? []).cast<Map<String, dynamic>>();
    final roots = sceneIndex < scenes.length
        ? (scenes[sceneIndex]['nodes'] as List? ?? []).cast<int>()
        : List<int>.generate(nodes.length, (i) => i);

    void visit(int nodeIndex, Mat4 parent) {
      if (nodeIndex < 0 || nodeIndex >= nodes.length) return;
      final node = nodes[nodeIndex];
      final world = parent * _nodeTransform(node);
      final meshIndex = node['mesh'] as int?;
      if (meshIndex != null && meshIndex < meshes.length) {
        _readMesh(meshes[meshIndex], world, accessors, bufferViews, bin, out);
      }
      for (final child in (node['children'] as List? ?? []).cast<int>()) {
        visit(child, world);
      }
    }

    for (final root in roots) {
      visit(root, Mat4.identity());
    }
  }

  Mat4 _nodeTransform(Map<String, dynamic> node) {
    final matrix = node['matrix'] as List?;
    if (matrix != null && matrix.length == 16) {
      return Mat4.fromColumnMajor(
        matrix.map((e) => (e as num).toDouble()).toList(),
      );
    }
    var m = Mat4.identity();
    final t = (node['translation'] as List?)?.cast<num>();
    final r = (node['rotation'] as List?)?.cast<num>();
    final s = (node['scale'] as List?)?.cast<num>();
    if (t != null && t.length == 3) {
      m = m *
          Mat4.translation(t[0].toDouble(), t[1].toDouble(), t[2].toDouble());
    }
    if (r != null && r.length == 4) {
      m = m *
          Mat4.rotationQuaternion(r[0].toDouble(), r[1].toDouble(),
              r[2].toDouble(), r[3].toDouble());
    }
    if (s != null && s.length == 3) {
      m = m * Mat4.scaling(s[0].toDouble(), s[1].toDouble(), s[2].toDouble());
    }
    return m;
  }

  void _readMesh(
    Map<String, dynamic> mesh,
    Mat4 transform,
    List<Map<String, dynamic>> accessors,
    List<Map<String, dynamic>> bufferViews,
    ByteData bin,
    List<MeshPart> out,
  ) {
    for (final prim
        in (mesh['primitives'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final mode = prim['mode'] as int? ?? 4;
      if (mode != 4) continue;
      final attrs =
          (prim['attributes'] as Map? ?? {}).cast<String, dynamic>();
      final posIndex = attrs['POSITION'] as int?;
      if (posIndex == null) continue;

      final posAcc = _Accessor(accessors[posIndex], bufferViews);
      final uvIndex = attrs['TEXCOORD_0'] as int?;
      final uvAcc =
          uvIndex != null ? _Accessor(accessors[uvIndex], bufferViews) : null;

      final vertices = <MeshVertex>[];
      for (var i = 0; i < posAcc.count; i++) {
        final p = transform.transformPoint(Vec3(
          posAcc.component(bin, i, 0),
          posAcc.component(bin, i, 1),
          posAcc.component(bin, i, 2),
        ));
        vertices.add(MeshVertex(
          p.x,
          p.y,
          p.z,
          uvAcc?.component(bin, i, 0) ?? 0,
          uvAcc?.component(bin, i, 1) ?? 0,
        ));
      }

      final indices = <int>[];
      final idxIndex = prim['indices'] as int?;
      if (idxIndex != null) {
        final idxAcc = _Accessor(accessors[idxIndex], bufferViews);
        for (var i = 0; i < idxAcc.count; i++) {
          indices.add(idxAcc.component(bin, i, 0).toInt());
        }
      } else {
        for (var i = 0; i < vertices.length; i++) {
          indices.add(i);
        }
      }

      out.add(MeshPart(
        vertices: vertices,
        indices: indices,
        material: prim['material'] as int? ?? 0,
      ));
    }
  }

  Future<AvatarMaterial> _decodeMaterial(
    Map<String, dynamic> mat,
    List<Map<String, dynamic>> textures,
    List<Map<String, dynamic>> images,
    List<Map<String, dynamic>> bufferViews,
    ByteData bin,
  ) async {
    final pbr =
        (mat['pbrMetallicRoughness'] as Map? ?? {}).cast<String, dynamic>();
    final factor = (pbr['baseColorFactor'] as List?)?.cast<num>();
    final color = factor != null && factor.length == 4
        ? Color.fromARGB(
            (factor[3] * 255).round().clamp(0, 255),
            (factor[0] * 255).round().clamp(0, 255),
            (factor[1] * 255).round().clamp(0, 255),
            (factor[2] * 255).round().clamp(0, 255),
          )
        : const Color(0xFFB0B0B0);

    ui.Image? image;
    final texIndex = (pbr['baseColorTexture'] as Map?)?['index'] as int?;
    if (texIndex != null && texIndex < textures.length) {
      final srcIndex = textures[texIndex]['source'] as int?;
      if (srcIndex != null && srcIndex < images.length) {
        image = await _decodeImageEntry(images[srcIndex], bufferViews, bin);
      }
    }
    return AvatarMaterial(color: color, image: image);
  }

  Future<ui.Image?> _decodeImageEntry(
    Map<String, dynamic> image,
    List<Map<String, dynamic>> bufferViews,
    ByteData bin,
  ) async {
    Uint8List? bytes;
    final bufferViewIndex = image['bufferView'] as int?;
    if (bufferViewIndex != null && bufferViewIndex < bufferViews.length) {
      final view = bufferViews[bufferViewIndex];
      final offset = view['byteOffset'] as int? ?? 0;
      final length = view['byteLength'] as int? ?? 0;
      bytes = Uint8List(length);
      for (var i = 0; i < length; i++) {
        bytes[i] = bin.getUint8(offset + i);
      }
    } else {
      final uri = image['uri'] as String?;
      if (uri != null && uri.startsWith('data:')) {
        final comma = uri.indexOf(',');
        if (comma >= 0) {
          bytes = base64Decode(uri.substring(comma + 1));
        }
      }
    }
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return await _decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}

/// Typed view into a glTF accessor.
class _Accessor {
  _Accessor(Map<String, dynamic> json, List<Map<String, dynamic>> bufferViews)
      : count = json['count'] as int? ?? 0,
        _componentType = json['componentType'] as int? ?? 5126,
        _normalized = json['normalized'] == true,
        _accessorOffset = json['byteOffset'] as int? ?? 0,
        _elementCount = switch (json['type'] as String? ?? 'SCALAR') {
          'SCALAR' => 1,
          'VEC2' => 2,
          'VEC3' => 3,
          'VEC4' => 4,
          'MAT4' => 16,
          _ => 1,
        },
        _componentSize = switch (json['componentType'] as int? ?? 5126) {
          5120 || 5121 => 1,
          5122 || 5123 => 2,
          _ => 4,
        },
        _viewOffset = _resolveView(json, bufferViews).$1,
        _stride = _resolveView(json, bufferViews).$2;

  static (int, int) _resolveView(
      Map<String, dynamic> json, List<Map<String, dynamic>> bufferViews) {
    final viewIndex = json['bufferView'] as int?;
    if (viewIndex == null || viewIndex >= bufferViews.length) {
      return (0, 0);
    }
    final view = bufferViews[viewIndex];
    return (
      view['byteOffset'] as int? ?? 0,
      view['byteStride'] as int? ?? 0,
    );
  }

  final int count;
  final int _componentType;
  final bool _normalized;
  final int _viewOffset;
  final int _accessorOffset;
  final int _stride;
  final int _elementCount;
  final int _componentSize;

  int get _effectiveStride =>
      _stride != 0 ? _stride : _elementCount * _componentSize;

  int _byteOffset(int index, int component) =>
      _viewOffset +
      _accessorOffset +
      index * _effectiveStride +
      component * _componentSize;

  double component(ByteData bin, int index, int component) {
    if (component >= _elementCount) return 0;
    final raw = switch (_componentType) {
      5120 => bin.getInt8(_byteOffset(index, component)).toDouble(),
      5121 => bin.getUint8(_byteOffset(index, component)).toDouble(),
      5122 => bin.getInt16(_byteOffset(index, component), Endian.little)
          .toDouble(),
      5123 => bin.getUint16(_byteOffset(index, component), Endian.little)
          .toDouble(),
      5125 => bin.getUint32(_byteOffset(index, component), Endian.little)
          .toDouble(),
      _ => bin.getFloat32(_byteOffset(index, component), Endian.little),
    };
    if (!_normalized) return raw;
    return switch (_componentType) {
      5120 => raw / 127.0,
      5121 => raw / 255.0,
      5122 => raw / 32767.0,
      5123 => raw / 65535.0,
      _ => raw,
    };
  }
}
