import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/api/roblox_api.dart';
import 'package:bin/render/avatar_assembler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

AssetLoader fakeLoader(Map<int, Uint8List> assets) =>
    (id) async => assets[id] ?? (throw StateError('no asset $id'));

AvatarSpec spec({
  String type = 'R6',
  Map<String, double> scales = const {},
  Map<String, int> colors = const {},
  List<(int, String)> assets = const [],
}) =>
    AvatarSpec(
        avatarType: type, scales: scales, bodyColors: colors, assets: assets);

/// v1.00 text mesh: a single unit-ish triangle.
Uint8List texMesh() => ascii.encode(
    'version 1.00\n1\n[0,2,0][0,1,0][0,0,0][2,0,0][0,1,0][1,0,0][0,0,2][0,1,0][1,1,0]');

Uint8List xmlAccessory(
    {int mesh = 100, int tex = 200, String attach = 'HatAttachment'}) {
  return utf8.encode('''
<roblox version="4">
  <Item class="Accessory">
    <Properties>
      <CoordinateFrame name="AttachmentPoint">
        <X>0</X><Y>-0.25</Y><Z>0.15</Z>
        <R00>1</R00><R01>0</R01><R02>0</R02>
        <R10>0</R10><R11>1</R11><R12>0</R12>
        <R20>0</R20><R21>0</R21><R22>1</R22>
      </CoordinateFrame>
      <string name="Name">Hat</string>
    </Properties>
    <Item class="Part">
      <Properties><string name="Name">Handle</string></Properties>
      <Item class="SpecialMesh">
        <Properties>
          <Content name="MeshId"><url>http://www.roblox.com/asset/?id=$mesh</url></Content>
          <Content name="TextureId"><url>http://www.roblox.com/asset/?id=$tex</url></Content>
          <Vector3 name="Scale"><X>1.1</X><Y>1.2</Y><Z>1.3</Z></Vector3>
          <Vector3 name="Offset"><X>0</X><Y>0.1</Y><Z>0</Z></Vector3>
          <Vector3 name="VertexColor"><X>1</X><Y>0.5</Y><Z>0</Z></Vector3>
        </Properties>
      </Item>
      <Item class="Attachment">
        <Properties><string name="Name">$attach</string></Properties>
      </Item>
    </Item>
  </Item>
</roblox>
''');
}

Uint8List xmlDecal(int tex) => utf8.encode('''
<roblox version="4">
  <Item class="Decal">
    <Properties><Content name="Texture"><url>http://www.roblox.com/asset/?id=$tex</url></Content></Properties>
  </Item>
</roblox>
''');

Uint8List xmlTemplate(String prop, int tex) => utf8.encode('''
<roblox version="4">
  <Item class="Shirt">
    <Properties><Content name="$prop"><url>http://www.roblox.com/asset/?id=$tex</url></Content></Properties>
  </Item>
</roblox>
''');

void main() {
  testWidgets('builds blocky R6 body with colors', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({}));
      final m = await a.build(spec(colors: {
        'headColorId': 226,
        'torsoColorId': 1017,
        'leftArmColorId': 26,
        'rightArmColorId': 26,
        'leftLegColorId': 28,
        'rightLegColorId': 28,
      }));
      // 5 limbs + head + face decal = 7 parts
      expect(m.parts.length, greaterThanOrEqualTo(6));
      expect(m.radius, greaterThan(0));
      expect(m.minY, lessThan(0.01));
    });
  });

  testWidgets('clothing and face textures apply', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        11: xmlTemplate('ShirtTemplate', 300),
        12: xmlTemplate('PantsTemplate', 301),
        13: xmlDecal(302),
        144075659: xmlDecal(303),
        300: testPng(),
        301: testPng(),
        302: testPng(),
        303: testPng(),
      }));
      final m = await a.build(spec(assets: [
        (11, 'Shirt'),
        (12, 'Pants'),
        (13, 'TShirt'),
      ]));
      final textured = m.materials.where((x) => x.image != null).length;
      expect(textured, greaterThanOrEqualTo(5));
    });
  });

  testWidgets('hat accessory lands on head', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        7: xmlAccessory(),
        100: texMesh(),
        200: testPng(),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [(7, 'Hat')]));
      // 6 body parts + face quad + hat
      expect(m.parts.length, 8);
      // hat verts sit above the head area
      final hat = m.parts.last;
      final maxY = hat.vertices.fold<double>(
          0, (acc, v) => v.y > acc ? v.y : acc);
      expect(maxY, greaterThan(4.0));
    });
  });

  testWidgets('unknown attachment and missing mesh still render',
      (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        7: xmlAccessory(mesh: 999, attach: 'CustomThing'),
        999: texMesh(),
        200: testPng(),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [(7, 'BackAccessory')]));
      expect(m.parts.length, 8);
    });
  });

  testWidgets('bad accessory and mesh failures are skipped', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        7: utf8.encode('not xml'),
        8: utf8.encode('<roblox version="4"><Item class="Folder"></Item></roblox>'),
        9: xmlAccessory(mesh: 998, tex: 997),
        // 998 missing from loader -> mesh fetch fails
        // accessory with no handle at all
        14: utf8.encode('<roblox version="4"><Item class="Accessory">'
            '<Properties><string name="Name">Empty</string></Properties>'
            '</Item></roblox>'),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [
        (7, 'Hat'),
        (8, 'NeckAccessory'),
        (9, 'WaistAccessory'),
        (14, 'FrontAccessory'),
      ]));
      expect(m.parts.length, 7); // body only
    });
  });

  testWidgets('handle without name and failed texture', (tester) async {
    await tester.runAsync(() async {
      // handle Part has no Name prop -> second scan in _findHandle;
      // texture id 999 is missing from the loader -> falls back untextured
      final xml = utf8.encode('''
<roblox version="4">
  <Item class="Accessory">
    <Properties>
      <CoordinateFrame name="AttachmentPoint">
        <X>0</X><Y>0</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02>
        <R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>
      </CoordinateFrame>
      <string name="Name">Acc</string>
    </Properties>
    <Item class="Part">
      <Item class="SpecialMesh">
        <Properties>
          <Content name="MeshId"><url>http://www.roblox.com/asset/?id=100</url></Content>
          <Content name="TextureId"><url>http://www.roblox.com/asset/?id=999</url></Content>
        </Properties>
      </Item>
      <Item class="Attachment">
        <Properties><string name="Name">NeckAttachment</string></Properties>
      </Item>
    </Item>
  </Item>
</roblox>
''');
      final a = AvatarAssembler(fakeLoader({
        7: xml,
        100: texMesh(),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [(7, 'NeckAccessory')]));
      expect(m.parts.length, 8);
      expect(m.materials.last.image, isNull);
    });
  });

  testWidgets('meshpart handle with raw color tint', (tester) async {
    await tester.runAsync(() async {
      final xml = utf8.encode('''
<roblox version="4">
  <Item class="Accessory">
    <Properties><string name="Name">Acc</string></Properties>
    <Item class="MeshPart">
      <Properties>
        <string name="Name">Handle</string>
        <Content name="MeshId"><url>http://www.roblox.com/asset/?id=100</url></Content>
        <Color3 name="Color"><R>200</R><G>100</G><B>50</B></Color3>
      </Properties>
    </Item>
  </Item>
</roblox>
''');
      final a = AvatarAssembler(fakeLoader({
        7: xml,
        100: texMesh(),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [(7, 'HatAccessory')]));
      expect(m.parts.length, 8);
      expect(m.materials.last.color.r, closeTo(200 / 255, 0.01));
    });
  });

  testWidgets('R15 package parts are used when present', (tester) async {
    await tester.runAsync(() async {
      final torso = buildR15Package([
        ('LowerTorso', 100),
        ('UpperTorso', 100),
      ], attachments: {
        'LowerTorso': {
          'LeftHipRigAttachment': [-0.4, -0.7, 0],
          'RightHipRigAttachment': [0.4, -0.7, 0],
        },
        'UpperTorso': {
          'NeckRigAttachment': [0, 0.8, 0],
          'LeftShoulderRigAttachment': [-1.1, 0.6, 0],
          'RightShoulderRigAttachment': [1.1, 0.6, 0],
        },
      });
      final arm = buildR15Package([
        ('LeftUpperArm', 100),
        ('LeftLowerArm', 100),
        ('LeftHand', 100),
      ], attachments: {
        'LeftUpperArm': {'LeftShoulderRigAttachment': [0, 0.5, 0]},
      });
      final leg = buildR15Package([
        ('LeftUpperLeg', 100),
        ('LeftLowerLeg', 100),
        ('LeftFoot', 100),
      ], attachments: {
        'LeftUpperLeg': {'LeftHipRigAttachment': [0, 0.8, 0]},
      });
      // the right-arm package has no CFrame props -> exercises ownFrame's
      // identity fallback
      final armNoCf = buildR15Package([
        ('RightUpperArm', 100),
        ('RightLowerArm', 100),
        ('RightHand', 100),
      ], cframes: false);
      final loader = fakeLoader({
        50: torso,
        51: arm,
        52: armNoCf,
        53: leg,
        54: leg,
        55: buildDynHeadPackage(),
        100: texMesh(),
        200: testPng(),
      });
      final a = AvatarAssembler(loader);
      final m = await a.build(spec(
          type: 'R15',
          scales: {'height': 1.1, 'width': 0.9, 'head': 1.2},
          assets: [
            (50, 'Torso'),
            (51, 'LeftArm'),
            (52, 'RightArm'),
            (53, 'LeftLeg'),
            (54, 'RightLeg'),
            (55, 'DynamicHead'),
          ]));
      // 8 named meshparts + dynamic head
      expect(m.parts.length, 12);
      expect(m.materials.first.image, isNotNull);
    });
  });

  testWidgets('rig attachments position cframe-less package parts',
      (tester) async {
    await tester.runAsync(() async {
      final torso = buildR15Package([
        ('LowerTorso', 100),
        ('UpperTorso', 100),
      ], attachments: {
        'LowerTorso': {
          'LeftHipRigAttachment': [-0.4, -0.7, 0],
          'RightHipRigAttachment': [0.4, -0.7, 0],
        },
        'UpperTorso': {
          'NeckRigAttachment': [0, 0.8, 0],
          'LeftShoulderRigAttachment': [-1.1, 0.6, 0],
          'RightShoulderRigAttachment': [1.1, 0.6, 0],
        },
      });
      final arm = buildR15Package([
        ('LeftUpperArm', 100),
        ('LeftLowerArm', 100),
        ('LeftHand', 100),
      ], attachments: {
        'LeftUpperArm': {'LeftShoulderRigAttachment': [0, 0.5, 0]},
      });
      final leg = buildR15Package([
        ('LeftUpperLeg', 100),
        ('LeftLowerLeg', 100),
        ('LeftFoot', 100),
      ], attachments: {
        'LeftUpperLeg': {'LeftHipRigAttachment': [0, 0.8, 0]},
      });
      // no cframes, but the shoulder attachments line up with the torso's
      final armChain = buildR15Package([
        ('RightUpperArm', 100),
        ('RightLowerArm', 100),
        ('RightHand', 100),
      ], cframes: false, attachments: {
        'RightUpperArm': {'RightShoulderRigAttachment': [0, 0.5, 0]},
      });
      final m = await AvatarAssembler(fakeLoader({
        50: torso,
        51: arm,
        52: armChain,
        53: leg,
        54: leg,
        100: texMesh(),
        200: testPng(),
      }))
          .build(spec(type: 'R15', assets: [
        (50, 'Torso'),
        (51, 'LeftArm'),
        (52, 'RightArm'),
        (53, 'LeftLeg'),
        (54, 'RightLeg'),
      ]));
      // 9 mesh parts + blocky head + face decal quad
      expect(m.parts.length, greaterThanOrEqualTo(9));
    });
  });

  testWidgets('tshirt decal wraps the package torso', (tester) async {
    await tester.runAsync(() async {
      // 'Torso' instead of UpperTorso exercises the neck-anchor fallback
      final torso = buildR15Package([
        ('LowerTorso', 100),
        ('Torso', 100),
      ]);
      final limb = buildR15Package([
        ('LeftUpperArm', 100),
        ('RightUpperArm', 100),
        ('LeftUpperLeg', 100),
        ('RightUpperLeg', 100),
      ]);
      final m = await AvatarAssembler(fakeLoader({
        50: torso,
        51: limb,
        52: limb,
        53: limb,
        54: limb,
        70: xmlDecal(300),
        100: texMesh(),
        200: testPng(),
        300: testPng(),
        144075659: xmlDecal(400),
        400: testPng(),
      }))
          .build(spec(type: 'R15', assets: [
        (50, 'Torso'),
        (51, 'LeftArm'),
        (52, 'RightArm'),
        (53, 'LeftLeg'),
        (54, 'RightLeg'),
        (70, 'TShirt'),
      ]));
      // 6 mesh parts + blocky head + face quad
      expect(m.parts.length, greaterThanOrEqualTo(8));
      expect(m.parts.any((p) => p.vertices.length == 4), isTrue);
    });
  });

  testWidgets('package parts without mesh fall back to blocky',
      (tester) async {
    await tester.runAsync(() async {
      final loader = fakeLoader({
        for (final id in [50, 51, 52, 53, 54, 55]) id: buildBinRbxm(),
        144075659: xmlDecal(400),
        400: testPng(),
      });
      final a = AvatarAssembler(loader);
      // buildBinRbxm yields a Part (not MeshPart) so nothing renders through
      // the package path; blocky fallback engages.
      final m = await a.build(spec(
          type: 'R15',
          assets: [
            (50, 'Torso'),
            (51, 'LeftArm'),
            (52, 'RightArm'),
            (53, 'LeftLeg'),
            (54, 'RightLeg'),
          ]));
      expect(m.parts.isNotEmpty, isTrue);
    });
  });

  testWidgets('package without torso parts falls back to blocky',
      (tester) async {
    await tester.runAsync(() async {
      final misc = buildR15Package([('Widget', 100)], cframes: false);
      final a = AvatarAssembler(fakeLoader({
        for (final id in [50, 51, 52, 53, 54]) id: misc,
        100: texMesh(),
        200: testPng(),
      }));
      final m = await a.build(spec(
          type: 'R15',
          assets: [
            (50, 'Torso'),
            (51, 'LeftArm'),
            (52, 'RightArm'),
            (53, 'LeftLeg'),
            (54, 'RightLeg'),
          ]));
      expect(m.parts.length, greaterThanOrEqualTo(6));
    });
  });

  testWidgets('broken package falls back to blocky', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        50: utf8.encode('garbage'),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(
          type: 'R15',
          assets: [
            (50, 'Torso'),
            (51, 'LeftArm'),
            (52, 'RightArm'),
            (53, 'LeftLeg'),
            (54, 'RightLeg'),
          ]));
      expect(m.parts.length, greaterThanOrEqualTo(6));
    });
  });

  testWidgets('meshpart handle without attachment point works', (tester) async {
    await tester.runAsync(() async {
      final handleXml = utf8.encode('''
<roblox version="4">
  <Item class="Accessory">
    <Properties><string name="Name">Acc</string></Properties>
    <Item class="MeshPart">
      <Properties>
        <string name="Name">Handle</string>
        <Content name="MeshId"><url>http://www.roblox.com/asset/?id=100</url></Content>
        <Content name="TextureID"><url>http://www.roblox.com/asset/?id=200</url></Content>
        <Color3 name="Color3uint8"><R>1</R><G>0.5</G><B>0</B></Color3>
      </Properties>
    </Item>
  </Item>
</roblox>
''');
      final a = AvatarAssembler(fakeLoader({
        7: handleXml,
        100: texMesh(),
        200: testPng(),
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(assets: [(7, 'HatAccessory')]));
      expect(m.parts.length, 8);
    });
  });

  testWidgets('worn face asset is used', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        60: xmlDecal(401),
        401: testPng(),
      }));
      final m = await a.build(spec(assets: [(60, 'Face')]));
      expect(m.materials.any((x) => x.image != null), isTrue);
    });
  });

  testWidgets('scales are applied', (tester) async {
    await tester.runAsync(() async {
      final a = AvatarAssembler(fakeLoader({
        144075659: xmlDecal(400),
        400: testPng(),
      }));
      final m = await a.build(spec(scales: {'height': 2.0, 'width': 1.0}));
      expect(m.center.y + m.radius, greaterThan(8));
    });
  });
}
