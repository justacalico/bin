import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;

import '../api/roblox_api.dart' show AvatarSpec;
import 'brick_colors.dart';
import 'glb_parser.dart';
import 'math3d.dart';
import 'rbx_mesh.dart';
import 'rbxm.dart';
import 'rig_geometry.dart';

/// Assembles a Roblox avatar from official API data: body parts, body colors,
/// clothing textures, accessories. Produces the same [AvatarModel] the
/// renderer consumes.
/// Loads an asset's raw bytes by catalog id.
typedef AssetLoader = Future<Uint8List> Function(int id);

class AvatarAssembler {
  AvatarAssembler(this.loadAsset,
      {Future<ui.Image> Function(Uint8List bytes)? imageDecoder})
      : _decodeImage = imageDecoder ?? _defaultDecode;

  final AssetLoader loadAsset;

  final Future<ui.Image> Function(Uint8List bytes) _decodeImage;

  static Future<ui.Image> _defaultDecode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  static const _wearables = {
    'Hat',
    'HatAccessory',
    'HairAccessory',
    'FaceAccessory',
    'NeckAccessory',
    'ShoulderAccessory',
    'FrontAccessory',
    'BackAccessory',
    'WaistAccessory',
    'JacketAccessory',
    'ShirtAccessory',
    'TShirtAccessory',
    'ShortsAccessory',
    'PantsAccessory',
    'SweaterAccessory',
    'DressSkirtAccessory',
    'LeftShoeAccessory',
    'RightShoeAccessory',
    'EyebrowAccessory',
    'EyelashAccessory',
    'LipstickAccessory',
  };

  static const _packageParts = {
    'Torso',
    'Head',
    'DynamicHead',
    'LeftArm',
    'RightArm',
    'LeftLeg',
    'RightLeg',
  };

  /// attachment name -> (body part, local offset)
  static const _attachments = <String, (String, Vec3)>{
    'HatAttachment': ('Head', Vec3(0, 0.6, 0)),
    'HairAttachment': ('Head', Vec3(0, 0.6, 0)),
    'FaceFrontAttachment': ('Head', Vec3(0, -0.1, -0.6)),
    'FaceCenterAttachment': ('Head', Vec3(0, 0, 0)),
    'NeckAttachment': ('Torso', Vec3(0, 1, 0)),
    'NeckFrontAttachment': ('Torso', Vec3(0, 0.5, -0.5)),
    'WaistFrontAttachment': ('Torso', Vec3(0, -0.5, -0.5)),
    'WaistCenterAttachment': ('Torso', Vec3(0, -0.5, 0)),
    'WaistBackAttachment': ('Torso', Vec3(0, -0.5, 0.5)),
    'BodyFrontAttachment': ('Torso', Vec3(0, 0, -0.5)),
    'BodyBackAttachment': ('Torso', Vec3(0, 0, 0.5)),
    'LeftShoulderAttachment': ('LeftArm', Vec3(0, 1, 0)),
    'RightShoulderAttachment': ('RightArm', Vec3(0, 1, 0)),
    'LeftCollarAttachment': ('Torso', Vec3(-1, 1, 0)),
    'RightCollarAttachment': ('Torso', Vec3(1, 1, 0)),
  };

  final _parts = <MeshPart>[];
  final _materials = <AvatarMaterial>[];
  final _partCenters = <String, Vec3>{};
  final _meshCache = <int, RbxMesh?>{};
  final _texCache = <int, ui.Image?>{};

  int _mat(Color color, [ui.Image? image]) {
    _materials.add(AvatarMaterial(color: color, image: image));
    return _materials.length - 1;
  }

  Color _brick(int? id) {
    final rgb = brickColors[id ?? 194];
    if (rgb == null) return const Color(0xFFA0A0A0);
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }

  Future<AvatarModel> build(AvatarSpec spec) async {
    _parts.clear();
    _materials.clear();
    _partCenters.clear();

    final partAssets = <String, int>{};
    final wearables = <int>[];
    int? shirtId, pantsId, tshirtId, faceId;

    for (final (id, type) in spec.assets) {
      if (_packageParts.contains(type)) {
        partAssets[type] = id;
      } else if (_wearables.contains(type)) {
        wearables.add(id);
      } else if (type == 'Shirt') {
        shirtId = id;
      } else if (type == 'Pants') {
        pantsId = id;
      } else if (type == 'TShirt') {
        tshirtId = id;
      } else if (type == 'Face') {
        faceId = id;
      }
    }

    // clothing textures
    ui.Image? shirtTex = await _templateImage(shirtId, 'ShirtTemplate');
    ui.Image? pantsTex = await _templateImage(pantsId, 'PantsTemplate');
    ui.Image? tshirtTex = await _decalImage(tshirtId);
    ui.Image? faceTex = await _decalImage(faceId ?? 144075659);

    final usePackage = spec.avatarType == 'R15' &&
        ['Torso', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg']
            .every(partAssets.containsKey);

    if (usePackage) {
      await _packageBody(spec, partAssets, tshirtTex, faceTex);
    } else {
      _blockyBody(spec, shirtTex, pantsTex, tshirtTex, faceTex);
    }

    for (final id in wearables) {
      await _wearable(id);
    }

    return _finish();
  }

  // ---- body ----

  void _blockyBody(AvatarSpec spec, ui.Image? shirt, ui.Image? pants,
      ui.Image? tshirt, ui.Image? face) {
    final h = spec.scales['height'] ?? 1.0;
    final w = spec.scales['width'] ?? 1.0;
    final d = spec.scales['depth'] ?? 1.0;
    final hs = spec.scales['head'] ?? 1.0;

    Color col(String part) => _brick(spec.bodyColors['${part}ColorId']);

    final torsoSize = Vec3(2 * w, 2 * h, 1 * d);
    final legSize = Vec3(1 * w, 2 * h, 1 * d);
    final armSize = Vec3(1 * w, 2 * h, 1 * d);

    _addBox('Torso', Vec3(0, 3 * h, 0), torsoSize, col('torso'),
        shirt: shirt, shirtUvs: true);
    _partCenters['Torso'] = Vec3(0, 3 * h, 0);

    _addBox('LeftLeg', Vec3(-0.5 * w, 1 * h, 0), legSize, col('leftLeg'),
        pants: pants, limb: 'left');
    _addBox('RightLeg', Vec3(0.5 * w, 1 * h, 0), legSize, col('rightLeg'),
        pants: pants, limb: 'right');
    _partCenters['LeftLeg'] = Vec3(-0.5 * w, 1 * h, 0);
    _partCenters['RightLeg'] = Vec3(0.5 * w, 1 * h, 0);

    _addBox('LeftArm', Vec3(-1.5 * w, 3 * h, 0), armSize, col('leftArm'),
        shirt: shirt, limb: 'left');
    _addBox('RightArm', Vec3(1.5 * w, 3 * h, 0), armSize, col('rightArm'),
        shirt: shirt, limb: 'right');
    _partCenters['LeftArm'] = Vec3(-1.5 * w, 3 * h, 0);
    _partCenters['RightArm'] = Vec3(1.5 * w, 3 * h, 0);

    // head: rounded box + face decal
    final headSize = Vec3(1.4 * hs, 1.3 * hs, 1.3 * hs);
    final headCenter = Vec3(0, 4.85 * h, 0);
    final (hv, hi) = roundedBoxMesh(headCenter, headSize, 0.35 * hs);
    _parts.add(MeshPart(
        vertices: hv, indices: hi, material: _mat(col('head'))));
    _partCenters['Head'] = headCenter;

    if (face != null) {
      final (fv, fi) = quadMesh(
          headCenter + Vec3(0, -0.05, -(headSize.z / 2 + 0.08)),
          const Vec3(0, 0, -1),
          1.1 * hs,
          1.1 * hs);
      _parts.add(MeshPart(
          vertices: fv, indices: fi, material: _mat(const Color(0xFFFFFFFF), face)));
    }
    if (tshirt != null) {
      final (fv, fi) = quadMesh(
          Vec3(0, 3 * h, -(torsoSize.z / 2 + 0.01)),
          const Vec3(0, 0, -1),
          torsoSize.x,
          torsoSize.y);
      _parts.add(MeshPart(
          vertices: fv,
          indices: fi,
          material: _mat(const Color(0xFFFFFFFF), tshirt)));
    }
  }

  void _addBox(String name, Vec3 center, Vec3 size, Color color,
      {ui.Image? shirt, ui.Image? pants, bool shirtUvs = false, String? limb}) {
    ui.Image? tex = shirt ?? pants;
    Map<String, (double, double, double, double)>? uvs;
    if (tex != null) {
      uvs = _templateUvs(shirtUvs ? 'torso' : limb ?? 'limb');
    }
    final (v, i) = boxMesh(center, size, faceUvs: uvs);
    _parts.add(MeshPart(vertices: v, indices: i, material: _mat(color, tex)));
  }

  // ---- package (R15) body ----

  Future<void> _packageBody(AvatarSpec spec, Map<String, int> partAssets,
      ui.Image? tshirtTex, ui.Image? faceTex) async {
    final h = spec.scales['height'] ?? 1.0;
    final w = spec.scales['width'] ?? 1.0;
    final d = spec.scales['depth'] ?? 1.0;
    final hs = spec.scales['head'] ?? 1.0;



    // R15 rigs attach sub-parts through named Attachment pairs: the child's
    // part frame satisfies childCF * childAttach = parentCF * parentAttach.
    const rig = <String, (String, String)>{
      'UpperTorso': ('LowerTorso', 'WaistRigAttachment'),
      'Head': ('UpperTorso', 'NeckRigAttachment'),
      'LeftUpperArm': ('UpperTorso', 'LeftShoulderRigAttachment'),
      'LeftLowerArm': ('LeftUpperArm', 'LeftElbowRigAttachment'),
      'LeftHand': ('LeftLowerArm', 'LeftWristRigAttachment'),
      'RightUpperArm': ('UpperTorso', 'RightShoulderRigAttachment'),
      'RightLowerArm': ('RightUpperArm', 'RightElbowRigAttachment'),
      'RightHand': ('RightLowerArm', 'RightWristRigAttachment'),
      'LeftUpperLeg': ('LowerTorso', 'LeftHipRigAttachment'),
      'LeftLowerLeg': ('LeftUpperLeg', 'LeftKneeRigAttachment'),
      'LeftFoot': ('LeftLowerLeg', 'LeftAnkleRigAttachment'),
      'RightUpperLeg': ('LowerTorso', 'RightHipRigAttachment'),
      'RightLowerLeg': ('RightUpperLeg', 'RightKneeRigAttachment'),
      'RightFoot': ('RightLowerLeg', 'RightAnkleRigAttachment'),
    };
    final parentColor = {
      'Head': 'head', 'UpperTorso': 'torso', 'LowerTorso': 'torso',
      'LeftUpperArm': 'leftArm', 'LeftLowerArm': 'leftArm', 'LeftHand': 'leftArm',
      'RightUpperArm': 'rightArm', 'RightLowerArm': 'rightArm', 'RightHand': 'rightArm',
      'LeftUpperLeg': 'leftLeg', 'LeftLowerLeg': 'leftLeg', 'LeftFoot': 'leftLeg',
      'RightUpperLeg': 'rightLeg', 'RightLowerLeg': 'rightLeg', 'RightFoot': 'rightLeg',
    };

    // collect mesh parts by name across all limb packages; dynamic heads are
    // a SpecialMesh + Vector3Value attachments rather than a MeshPart
    final partsByName = <String, RbxmInstance>{};
    final attachments = <String, Map<String, Mat4>>{};
    RbxmInstance? dynHead;
    final dynAttach = <String, Vec3>{};
    var failed = false;
    for (final e in partAssets.entries) {
      try {
        for (final node in readRbxm(await loadAsset(e.value))) {
          if (node.className == 'AnimationPackage' ||
              node.className == 'RbxAnimationClip') {
            continue;
          }
          for (final inst in node.walk()) {
            if (inst.className == 'MeshPart') {
              final name = inst.propString('Name');
              if (name != null) {
                partsByName[name] = inst;
                final atts = <String, Mat4>{};
                for (final child in inst.children) {
                  if (child.className == 'Attachment') {
                    final n = child.propString('Name');
                    final cf = child.propCFrame('CFrame');
                    if (n != null && cf != null) atts[n] = cframeMat(cf);
                  }
                }
                attachments[name] = atts;
              }
            }
            if (e.key == 'DynamicHead' || e.key == 'Head') {
              if (inst.className == 'SpecialMesh') {
                dynHead = inst;
              } else if (inst.className == 'Vector3Value') {
                final n = inst.propString('Name');
                final v = inst.propVec('Value');
                if (n != null && v != null && v.length >= 3) {
                  dynAttach[n] = Vec3(v[0], v[1], v[2]);
                }
              }
            }
          }
        }
      } catch (_) {
        // one dead package must not kill the rest; the rig falls back to
        // blocky only if no usable parts came through
        if (partsByName.isEmpty) failed = true;
      }
    }

    // packages carry authored CFrames for every part; the rig-attachment
    // chain is only a fallback for parts with no CFrame prop
    final frames = <String, Mat4>{};
    Mat4 ownFrame(RbxmInstance inst) =>
        cframeMat(inst.propCFrame('CFrame') ??
            [0.0, 0.0, 0.0, 1, 0, 0, 0, 1, 0, 0, 0, 1]);
    for (final e in partsByName.entries) {
      frames[e.key] = ownFrame(e.value);
    }
    for (var iter = 0; iter < 4; iter++) {
      for (final e in rig.entries) {
        final inst = partsByName[e.key];
        final parentCF = frames[e.value.$1];
        if (inst == null || parentCF == null) continue;
        if (inst.propCFrame('CFrame') != null) continue;
        final pa = attachments[e.value.$1]?[e.value.$2];
        final ca = attachments[e.key]?[e.value.$2];
        if (pa != null && ca != null) {
          frames[e.key] = parentCF * pa * rigidInverse(ca);
        }
      }
    }
    // a package rig without a torso anchor is broken; fall back entirely
    if (frames.isEmpty ||
        !(frames.containsKey('LowerTorso') ||
            frames.containsKey('UpperTorso') ||
            frames.containsKey('Torso'))) {
      failed = true;
    }

    if (!failed) {
      // package limb UVs are authored for their own texture, not the
      // classic clothing template, so clothing stays on the part textures
      final sm = Mat4.scaling(w, h, d);
      for (final e in partsByName.entries) {
        final inst = e.value;
        final meshId = _assetIdFrom(inst.propString('MeshId'));
        if (meshId == null) continue;
        final mesh = await _mesh(meshId);
        if (mesh == null) continue;
        final texId = _assetIdFrom(inst.propString('TextureID'));
        final tex = texId == null ? null : await _texture(texId);
        final cf = frames[e.key] ?? ownFrame(inst);
        final headScale = e.key == 'Head' ? hs : 1.0;
        final m = sm * cf * Mat4.scaling(headScale, headScale, headScale);
        final colorKey = parentColor[e.key] ?? 'torso';
        _parts.add(MeshPart(
            vertices: transformVerts(mesh.vertices, m),
            indices: mesh.indices,
            material: _mat(_brick(spec.bodyColors['${colorKey}ColorId']), tex)));
        _partCenters[e.key] = sm.transformPoint(cf.transformPoint(Vec3.zero));
      }
      // t-shirt graphic on the torso front
      final torsoC = _partCenters['UpperTorso'] ?? _partCenters['Torso'];
      if (tshirtTex != null && torsoC != null) {
        final depth = d * 0.6;
        final (fv, fi) = quadMesh(torsoC + Vec3(0, 0, -depth), const Vec3(0, 0, -1),
            1.5 * w, 1.5 * h);
        _parts.add(MeshPart(
            vertices: fv, indices: fi, material: _mat(const Color(0xFFFFFFFF), tshirtTex)));
      }
      // dynamic head hangs off the torso's neck attachment
      var hasHead = _partCenters.containsKey('Head');
      if (dynHead != null) {
        final meshId = _assetIdFrom(dynHead.propString('MeshId'));
        if (meshId != null) {
          final mesh = await _mesh(meshId);
          if (mesh != null) {
            final texId = _assetIdFrom(dynHead.propString('TextureId') ?? dynHead.propString('TextureID'));
            final tex = texId == null ? null : await _texture(texId);
            final neck = dynAttach['NeckRigAttachment'] ?? const Vec3(0, -0.5, 0);
            final parentNeck = attachments['UpperTorso']?['NeckRigAttachment'];
            final headCF = (parentNeck != null
                    ? frames['UpperTorso']! * parentNeck
                    : frames['UpperTorso'] ?? Mat4.identity()) *
                Mat4.translation(-neck.x, -neck.y, -neck.z);
            final m = sm * headCF * Mat4.scaling(hs, hs, hs);
            _parts.add(MeshPart(
                vertices: transformVerts(mesh.vertices, m),
                indices: mesh.indices,
                material: _mat(_brick(spec.bodyColors['headColorId']), tex)));
            _partCenters['Head'] =
                sm.transformPoint(headCF.transformPoint(Vec3.zero));
            hasHead = true;
          }
        }
      }
      // no head part at all -> blocky head anchored on the torso's neck
      if (!hasHead) {
        final headSize = Vec3(1.4 * hs, 1.3 * hs, 1.3 * hs);
        final neckLocal = dynAttach['NeckRigAttachment'] ??
            attachments['UpperTorso']?['NeckRigAttachment']
                ?.transformPoint(Vec3.zero) ??
            const Vec3(0, 0.5, 0);
        final neck = frames['UpperTorso']?.transformPoint(neckLocal) ??
            _partCenters['UpperTorso'] ??
            Vec3(0, 3.2 * h, 0);
        final headC = neck + Vec3(0, headSize.y * 0.55, 0);
        final (hv, hi) = roundedBoxMesh(headC, headSize, 0.35 * hs);
        _parts.add(MeshPart(
            vertices: hv,
            indices: hi,
            material: _mat(_brick(spec.bodyColors['headColorId']))));
        _partCenters['Head'] = headC;
        if (faceTex != null) {
          final (fv, fi) = quadMesh(
              headC + Vec3(0, -0.05, -(headSize.z / 2 + 0.08)),
              const Vec3(0, 0, -1), 1.1 * hs, 1.1 * hs);
          _parts.add(MeshPart(
              vertices: fv,
              indices: fi,
              material: _mat(const Color(0xFFFFFFFF), faceTex)));
        }
      }
    }
    // package could not provide real limb meshes; fall back to blocky
    if (failed || _parts.isEmpty) {
      _parts.clear();
      _materials.clear();
      _partCenters.clear();
      _blockyBody(spec, null, null, null, null);
      return;
    }
    _partCenters.putIfAbsent('Torso', () => Vec3(0, 3.2 * h, 0));
    _partCenters.putIfAbsent('Head', () => Vec3(0, 5.2 * h, 0));
    _partCenters.putIfAbsent('LeftArm', () => Vec3(-1.5 * w, 3 * h, 0));
    _partCenters.putIfAbsent('RightArm', () => Vec3(1.5 * w, 3 * h, 0));
  }

  // ---- accessories ----

  Future<void> _wearable(int assetId) async {
    List<RbxmInstance> roots;
    try {
      roots = readRbxm(await loadAsset(assetId));
    } catch (_) {
      return;
    }
    for (final root in roots) {
      if (root.className != 'Accessory' && root.className != 'Hat') continue;
      final handle = _findHandle(root);
      if (handle == null) continue;
      final attachName = _attachmentName(handle) ?? 'HatAttachment';
      final (partName, offset) =
          _attachments[attachName] ?? ('Head', const Vec3(0, 0.6, 0));
      final partCenter = _partCenters[partName] ?? _partCenters['Head'] ?? Vec3.zero;
      final partCF = Mat4.translation(partCenter.x, partCenter.y, partCenter.z);
      final attachCF = Mat4.translation(offset.x, offset.y, offset.z);
      final accPoint = root.propCFrame('AttachmentPoint') ??
          [0.0, 0.0, 0.0, 1, 0, 0, 0, 1, 0, 0, 0, 1];
      final handleCF = partCF * attachCF * rigidInverse(cframeMat(accPoint));
      await _emitHandle(handle, handleCF);
    }
  }

  RbxmInstance? _findHandle(RbxmInstance acc) {
    for (final inst in acc.walk()) {
      if (inst.props['Name'] == 'Handle') return inst;
    }
    for (final inst in acc.walk()) {
      if (inst.className == 'Part' || inst.className == 'MeshPart') return inst;
    }
    return null;
  }

  String? _attachmentName(RbxmInstance handle) {
    for (final inst in handle.children) {
      if (inst.className == 'Attachment') {
        return inst.props['Name'] as String?;
      }
    }
    return null;
  }

  Future<void> _emitHandle(RbxmInstance handle, Mat4 handleCF) async {
    final special = handle.findClass('SpecialMesh');
    int? meshId;
    int? texId;
    Vec3 scale = const Vec3(1, 1, 1);
    Vec3 offset = const Vec3(0, 0, 0);
    Color tint = const Color(0xFFFFFFFF);
    if (special != null) {
      meshId = _assetIdFrom(special.propString('MeshId'));
      texId = _assetIdFrom(special.propString('TextureId'));
      final s = special.propVec('Scale');
      if (s != null && s.length >= 3) scale = Vec3(s[0], s[1], s[2]);
      final o = special.propVec('Offset');
      if (o != null && o.length >= 3) offset = Vec3(o[0], o[1], o[2]);
      final vc = special.propVec('VertexColor');
      if (vc != null && vc.length >= 3) {
        tint = Color.fromARGB(
            255, (vc[0] * 255).round(), (vc[1] * 255).round(), (vc[2] * 255).round());
      }
    } else if (handle.className == 'MeshPart') {
      meshId = _assetIdFrom(handle.propString('MeshId'));
      texId = _assetIdFrom(handle.propString('TextureID'));
      final c = handle.propVec('Color3uint8') ?? handle.propVec('Color');
      if (c != null && c.length >= 3) {
        tint = c[0] > 1.0
            ? Color.fromARGB(
                255, c[0].round(), c[1].round(), c[2].round())
            : Color.fromARGB(
                255, (c[0] * 255).round(), (c[1] * 255).round(), (c[2] * 255).round());
      }
    }
    if (meshId == null) return;
    final mesh = await _mesh(meshId);
    if (mesh == null) return;
    final tex = texId == null ? null : await _texture(texId);
    final m = handleCF *
        Mat4.translation(offset.x, offset.y, offset.z) *
        Mat4.scaling(scale.x, scale.y, scale.z);
    _parts.add(MeshPart(
        vertices: transformVerts(mesh.vertices, m),
        indices: mesh.indices,
        material: _mat(tint, tex)));
  }

  // ---- asset helpers ----

  int? _assetIdFrom(String? content) {
    if (content == null) return null;
    final m = RegExp(r'(?:asset/?\?id=|rbxassetid://)(\d+)').firstMatch(content);
    return m == null ? null : int.parse(m.group(1)!);
  }

  Future<RbxMesh?> _mesh(int id) async {
    if (_meshCache.containsKey(id)) return _meshCache[id];
    try {
      return _meshCache[id] = parseRbxMesh(await loadAsset(id));
    } catch (_) {
      return _meshCache[id] = null;
    }
  }

  Future<ui.Image?> _texture(int id) async {
    if (_texCache.containsKey(id)) return _texCache[id];
    try {
      final img = await _decodeImage(await loadAsset(id));
      // some bundles ship a fully-transparent placeholder texture; a real
      // color is better than invisible parts
      if (await _isFullyTransparent(img)) return _texCache[id] = null;
      return _texCache[id] = img;
    } catch (_) {
      return _texCache[id] = null;
    }
  }

  Future<bool> _isFullyTransparent(ui.Image img) async {
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      final px = data.buffer.asUint8List();
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] > 0) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Shirt/Pants assets are rbxm containing a template Content url.
  Future<ui.Image?> _templateImage(int? id, String prop) async {
    if (id == null) return null;
    try {
      for (final root in readRbxm(await loadAsset(id))) {
        for (final inst in root.walk()) {
          final url = inst.propString(prop);
          final tid = _assetIdFrom(url);
          if (tid != null) return await _texture(tid);
        }
      }
    } catch (_) {}
    return null;
  }

  /// TShirt/Face assets are rbxm containing a Decal/Texture url.
  Future<ui.Image?> _decalImage(int? id) async {
    if (id == null) return null;
    try {
      for (final root in readRbxm(await loadAsset(id))) {
        for (final inst in root.walk()) {
          final url =
              inst.propString('Texture') ?? inst.propString('TextureId');
          final tid = _assetIdFrom(url);
          if (tid != null) return await _texture(tid);
        }
      }
    } catch (_) {}
    return null;
  }

  // ---- shirt template UVs ----

  /// Classic 585x559 template regions, normalized and v-flipped.
  Map<String, (double, double, double, double)> _templateUvs(String region) {
    (double, double, double, double) r(double x, double y, double w, double h) =>
        (x / 585, y / 559, (x + w) / 585, (y + h) / 559);
    // the avatar's front is -Z in Roblox space, so 'nz' gets the front
    // region and 'pz' the back
    const torso = {
      'nz': (231, 74, 128, 128), // front
      'pz': (427, 74, 128, 128), // back
      'px': (359, 74, 64, 128), // left side
      'nx': (163, 74, 64, 128), // right side
      'py': (231, 8, 128, 66), // top
      'ny': (231, 202, 128, 66), // bottom
    };
    const limbLeft = {
      'nz': (372, 355, 64, 128),
      'pz': (500, 355, 64, 128),
      'px': (436, 355, 64, 128),
      'nx': (308, 355, 64, 128),
      'py': (308, 290, 64, 64),
      'ny': (308, 483, 64, 64),
    };
    const limbRight = {
      'nz': (84, 355, 64, 128),
      'pz': (212, 355, 64, 128),
      'px': (148, 355, 64, 128),
      'nx': (20, 355, 64, 128),
      'py': (217, 290, 64, 64),
      'ny': (217, 483, 64, 64),
    };
    final src = region == 'torso'
        ? torso
        : region == 'left'
            ? limbLeft
            : limbRight;
    return {
      for (final e in src.entries)
        e.key: r(e.value.$1.toDouble(), e.value.$2.toDouble(),
            e.value.$3.toDouble(), e.value.$4.toDouble()),
    };
  }

  AvatarModel _finish() {
    // Roblox faces -Z; flip the world so the avatar faces the camera like the
    // glTF models did.
    for (final part in _parts) {
      for (var i = 0; i < part.vertices.length; i++) {
        final v = part.vertices[i];
        part.vertices[i] = MeshVertex(v.x, v.y, -v.z, v.u, v.v);
      }
      for (var i = 0; i + 2 < part.indices.length; i += 3) {
        final t = part.indices[i + 1];
        part.indices[i + 1] = part.indices[i + 2];
        part.indices[i + 2] = t;
      }
    }
    var min = const Vec3(double.infinity, double.infinity, double.infinity);
    var max = min * -1;
    for (final part in _parts) {
      for (final v in part.vertices) {
        min = Vec3(math.min(min.x, v.x), math.min(min.y, v.y), math.min(min.z, v.z));
        max = Vec3(math.max(max.x, v.x), math.max(max.y, v.y), math.max(max.z, v.z));
      }
    }
    final center = (min + max) * 0.5;
    var radius = 0.0;
    for (final part in _parts) {
      for (final v in part.vertices) {
        final dd = (Vec3(v.x, v.y, v.z) - center).length;
        if (dd > radius) radius = dd;
      }
    }
    if (radius == 0) radius = 1;
    return AvatarModel(
      parts: _parts,
      materials: _materials,
      center: center,
      radius: radius,
      minY: min.y,
    );
  }
}


