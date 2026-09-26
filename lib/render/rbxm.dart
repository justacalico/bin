import 'dart:typed_data';

import 'rbxm_bin.dart';
import 'rbxm_xml.dart';

/// A stripped-down Roblox instance tree. Properties are decoded only for the
/// types the avatar pipeline needs; everything else is dropped.
class RbxmInstance {
  RbxmInstance(this.className, this.referent);

  final String className;
  final int referent;
  final Map<String, dynamic> props = {};
  final List<RbxmInstance> children = [];

  String? propString(String name) => props[name] as String?;
  List<double>? propVec(String name) => (props[name] as List?)?.cast<double>();

  /// CFrames are stored as [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21,
  /// r22].
  List<double>? propCFrame(String name) => propVec(name);

  RbxmInstance? findChild(String name) {
    for (final c in children) {
      if (c.props['Name'] == name) return c;
    }
    return null;
  }

  RbxmInstance? findClass(String className) {
    for (final c in children) {
      if (c.className == className) return c;
    }
    return null;
  }

  Iterable<RbxmInstance> walk() sync* {
    yield this;
    for (final c in children) {
      yield* c.walk();
    }
  }
}

/// Parses either an XML (.rbxmx) or binary (.rbxm) file into instances.
List<RbxmInstance> readRbxm(Uint8List bytes) {
  if (bytes.length >= 8 && bytes[0] == 0x3C && bytes[7] == 0x21) {
    return RbxmBinReader().read(bytes);
  }
  var i = 0;
  while (i < bytes.length && bytes[i] <= 0x20) {
    i++;
  }
  if (i < bytes.length && bytes[i] == 0x3C) {
    return RbxmXmlReader().read(String.fromCharCodes(bytes));
  }
  throw const FormatException('not an rbxm file');
}
