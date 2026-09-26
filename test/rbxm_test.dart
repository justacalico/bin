import 'dart:convert';
import 'dart:typed_data';

import 'package:bin/render/rbxm.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// ---- binary test builder ----

const _xml = '''
<roblox version="4">
  <Item class="Accessory" referent="RBX0">
    <Properties>
      <CoordinateFrame name="AttachmentPoint">
        <X>0</X><Y>-0.25</Y><Z>0.15</Z>
        <R00>1</R00><R01>0</R01><R02>0</R02>
        <R10>0</R10><R11>1</R11><R12>0</R12>
        <R20>0</R20><R21>0</R21><R22>1</R22>
      </CoordinateFrame>
      <string name="Name">BCHardHat</string>
      <float name="Empty"/>
      <weird>ignored text</weird>
      <Rect2D name="Zone"><xmin>0</xmin></Rect2D>
    </Properties>
    <Item class="Part" referent="RBX1">
      <Properties>
        <string name="Name">Handle</string>
        <Vector3 name="size"><X>1</X><Y>2</Y><Z>3</Z></Vector3>
        <Content name="CData"><url>http://www.roblox.com/asset/?id=1073659</url></Content>
        <Content name="Nothing"><null></null></Content>
        <bool name="Anchored">false</bool>
        <float name="Elasticity">0.5</float>
        <token name="FormFactor">3</token>
        <int name="BrickColor">194</int>
        <ProtectedString name="Secret">hid</ProtectedString>
        <double name="D">2.5</double>
        <Color3 name="Tint"><R>1</R><G>0.5</G></Color3>
      </Properties>
      <Item class="Attachment" referent="RBX2">
        <Properties><string name="Name">HatAttachment</string></Properties>
      </Item>
    </Item>
  </Item>
</roblox>
''';

void main() {
  group('xml', () {
    test('parses accessory tree with cframe and content', () {
      final roots = readRbxm(Uint8List.fromList(utf8.encode(_xml)));
      expect(roots.length, 1);
      final acc = roots[0];
      expect(acc.className, 'Accessory');
      expect(acc.propString('Name'), 'BCHardHat');
      final cf = acc.propCFrame('AttachmentPoint')!;
      expect(cf[1], -0.25);
      expect(cf[3], 1.0);
      final handle = acc.findChild('Handle')!;
      expect(handle.className, 'Part');
      expect(handle.propVec('size'), [1.0, 2.0, 3.0]);
      expect(handle.props['Anchored'], false);
      expect(handle.props['Elasticity'], 0.5);
      expect(handle.props['FormFactor'], 3);
      expect(handle.props['BrickColor'], 194);
      expect(handle.propString('Secret'), 'hid');
      expect(handle.props['D'], 2.5);
      expect(handle.propVec('Tint'), [1.0, 0.5, 0.0]);
      expect(handle.propString('CData'),
          'http://www.roblox.com/asset/?id=1073659');
      expect(handle.propString('Nothing'), isNull);
      expect(handle.findClass('Attachment')!.propString('Name'),
          'HatAttachment');
      expect(acc.findChild('nope'), isNull);
      expect(acc.findClass('nope'), isNull);
      expect(acc.walk().length, 3);
    });

    test('unterminated document stops cleanly', () {
      final roots = readRbxm(
          Uint8List.fromList(utf8.encode('<Item class="Part"><string name=')));
      expect(roots, isEmpty);
      // prop whose close tag never arrives is consumed to EOF
      final r2 = readRbxm(Uint8List.fromList(utf8.encode(
          '<Item class="Part"><Properties><string name="A">text')));
      expect(r2.single.propString('A'), 'text');
    });
  });

  group('binary', () {
    test('parses inst/prop/prnt into tree', () {
      final roots = readRbxm(buildBinRbxm());
      expect(roots.length, 1);
      final acc = roots[0];
      expect(acc.className, 'Accessory');
      expect(acc.propString('Name'), 'BCHardHat');
      final cf = acc.propCFrame('AttachmentPoint')!;
      expect(cf[1], -0.25);
      expect(cf[2], closeTo(0.15, 1e-6));
      expect(acc.propVec('OtherCFrame')![0], 1.0);
      expect(acc.propVec('FallbackCFrame')![3], 1.0);
      expect(acc.propString('Shared'), 'sharedValue');
      expect(acc.props['Big'], 123456789);
      expect(acc.propString('Protected'), 'prot');
      final part = acc.children.single;
      expect(part.className, 'Part');
      expect(part.propVec('Size'), [1.0, 2.0, 3.0]);
      expect(part.props['Anchored'], true);
      expect(part.props['BrickColor'], 194);
      expect(part.props['SurfaceType'], 2);
      expect(part.props['FormFactor'], 3);
      expect(part.props['Friction'], 0.5);
      expect(part.props['Damage'], -7);
      expect(part.propVec('Color3uint8'), [0.5, 0.25, 0.75]);
      expect(part.propVec('Whatever2'), [4.0, 5.0]);
      expect(acc.props.containsKey('SomeThing'), isFalse);
    });

    test('rejects non-rbxm', () {
      expect(() => readRbxm(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<FormatException>()));
      expect(() => readRbxm(Uint8List(0)), throwsA(isA<FormatException>()));
      expect(
          () => readRbxm(Uint8List.fromList(ascii.encode('<roblox!'))),
          throwsA(isA<FormatException>()));
      // truncated chunk table parses as empty rather than crashing
      expect(
          readRbxm(Uint8List.fromList(
              ascii.encode('<roblox!') + List.filled(40, 0))),
          isEmpty);
    });
  });
}
