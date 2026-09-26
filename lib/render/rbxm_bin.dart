import 'dart:typed_data';

import 'lz4.dart';
import 'rbxm.dart';

/// Reader for binary .rbxm files (what assetdelivery serves for newer items
/// like R15 limb packages). Decodes the chunks needed by the avatar pipeline:
/// INST, PROP, PRNT, SSTR. Unknown property types are skipped per-chunk.
class RbxmBinReader {
  Uint8List _data = Uint8List(0);
  int _pos = 0;

  final _classes = <int, String>{};
  final _instances = <int, RbxmInstance>{};
  final _sharedStrings = <String>[];
  final _parents = <int, int>{};

  List<RbxmInstance> read(Uint8List bytes) {
    _data = bytes;
    _pos = 0;
    if (bytes.length < 32 || String.fromCharCodes(bytes.sublist(0, 7)) != '<roblox') {
      throw FormatException('not an rbxm file');
    }
    _pos = 14; // magic
    _u16(); // version
    _u32(); // numTypes
    _u32(); // numInstances
    _pos += 8; // reserved

    while (_pos + 16 <= _data.length) {
      final name = String.fromCharCodes(_data.sublist(_pos, _pos + 4));
      _pos += 4;
      final compressedLen = _u32();
      final uncompressedLen = _u32();
      _u32(); // reserved
      Uint8List body;
      if (compressedLen > 0) {
        body = lz4Decompress(
            _data.sublist(_pos, _pos + compressedLen), uncompressedLen);
        _pos += compressedLen;
      } else {
        body = _data.sublist(_pos, _pos + uncompressedLen);
        _pos += uncompressedLen;
      }
      if (name == 'END\u0000' || name.startsWith('END')) break;
      _chunk(name, body);
    }

    final roots = <RbxmInstance>[];
    for (final inst in _instances.values) {
      final parentId = _parents[inst.referent] ?? -1;
      final parent = _instances[parentId];
      if (parent == null) {
        roots.add(inst);
      } else {
        parent.children.add(inst);
      }
    }
    return roots;
  }

  void _chunk(String name, Uint8List body) {
    final r = _Reader(body);
    switch (name) {
      case 'SSTR':
        r.u32(); // version
        final count = r.u32();
        for (var i = 0; i < count; i++) {
          r.skip(16);
          _sharedStrings.add(r.str());
        }
      case 'INST':
        final typeId = r.u32();
        final className = r.str();
        r.u8(); // format marker
        final count = r.u32();
        _classes[typeId] = className;
        var ref = 0;
        for (final d in r.interleavedI32(count)) {
          ref += d; // referents are delta-encoded
          _instances[ref] = RbxmInstance(className, ref);
        }
      case 'PROP':
        _prop(r);
      case 'PRNT':
        r.u8();
        final count = r.u32();
        final children = r.interleavedI32(count);
        final parents = r.interleavedI32(count);
        for (var i = 0; i < count; i++) {
          _parents[children[i]] = parents[i];
        }
    }
  }

  void _prop(_Reader r) {
    final typeId = r.u32();
    final propName = r.str();
    final propType = r.u8();
    // map iteration is insertion order = INST order = PROP order
    final refs = _instances.values
        .where((i) => i.className == _classes[typeId])
        .toList();

    List<dynamic>? values;
    switch (propType) {
      case 0x01: // String / Content / ProtectedString
        values = [for (var i = 0; i < refs.length; i++) r.str()];
      case 0x02: // Bool
        values = [for (var i = 0; i < refs.length; i++) r.u8() != 0];
      case 0x03: // Int32
        values = r.interleavedI32(refs.length);
      case 0x04: // Float
        values = r.interleavedF32(refs.length);
      case 0x0B: // BrickColor
      case 0x11: // Enum token
      case 0x1B: // enum
        values = r.interleavedU32(refs.length);
      case 0x0C: // Color3
        values = _interleavedVec(r, refs.length, 3);
      case 0x0D: // Vector2
        values = _interleavedVec(r, refs.length, 2);
      case 0x0E: // Vector3
        values = _interleavedVec(r, refs.length, 3);
      case 0x10: // CFrame
        values = _cframes(r, refs.length);
      case 0x1D: // Int64
        values = r.interleavedI64(refs.length);
      case 0x1E: // SharedString
        final idxs = r.interleavedU32(refs.length);
        values = [
          for (final i in idxs)
            i < _sharedStrings.length ? _sharedStrings[i] : ''
        ];
      case 0x1F: // ProtectedString
        values = [for (var i = 0; i < refs.length; i++) r.str()];
      default:
        return;
    }
    for (var i = 0; i < refs.length && i < values.length; i++) {
      refs[i].props[propName] = values[i];
    }
  }

  List<List<double>> _interleavedVec(_Reader r, int count, int n) {
    final out = List.generate(count, (_) => List<double>.filled(n, 0));
    for (var c = 0; c < n; c++) {
      final col = r.interleavedF32(count);
      for (var i = 0; i < count; i++) {
        out[i][c] = col[i];
      }
    }
    return out;
  }

  List<List<double>> _cframes(_Reader r, int count) {
    final rots = <List<double>>[];
    for (var i = 0; i < count; i++) {
      final id = r.u8();
      if (id == 0) {
        rots.add(List.generate(9, (_) => r.f32()));
      } else {
        rots.add(_rotations[id] ?? _rotations[0x02]!);
      }
    }
    final positions = _interleavedVec(r, count, 3);
    return [
      for (var i = 0; i < count; i++) [...positions[i], ...rots[i]]
    ];
  }

  int _u16() {
    final v = _data[_pos] | (_data[_pos + 1] << 8);
    _pos += 2;
    return v;
  }

  int _u32() {
    final v = _data[_pos] |
        (_data[_pos + 1] << 8) |
        (_data[_pos + 2] << 16) |
        (_data[_pos + 3] << 24);
    _pos += 4;
    return v;
  }

  /// Axis-aligned rotation presets indexed by the rotation byte in CFrame
  /// values. Unknown ids fall back to identity.
  static const _rotations = <int, List<double>>{
    0x02: [1, 0, 0, 0, 1, 0, 0, 0, 1],
    0x03: [1, 0, 0, 0, 0, -1, 0, 1, 0],
    0x05: [1, 0, 0, 0, 0, 1, 0, -1, 0],
    0x06: [1, 0, 0, 0, -1, 0, 0, 0, -1],
    0x07: [1, 0, 0, 0, -1, 0, 0, 0, 1],
    0x09: [0, 1, 0, 1, 0, 0, 0, 0, -1],
    0x0A: [0, -1, 0, 1, 0, 0, 0, 0, 1],
    0x0C: [0, 0, 1, 1, 0, 0, 0, 1, 0],
    0x0D: [0, 0, -1, 1, 0, 0, 0, 0, -1],
    0x0E: [0, -1, 0, -1, 0, 0, 0, 0, -1],
    0x10: [0, 1, 0, 0, 0, 1, 1, 0, 0],
    0x11: [0, 0, -1, 0, -1, 0, -1, 0, 0],
    0x13: [0, -1, 0, 0, 0, -1, 1, 0, 0],
    0x14: [0, 0, 1, 0, -1, 0, -1, 0, 0],
    0x17: [0, 0, -1, 0, 1, 0, 1, 0, 0],
    0x18: [-1, 0, 0, 0, 0, -1, 0, -1, 0],
    0x19: [-1, 0, 0, 0, -1, 0, 0, 0, 1],
    0x1B: [-1, 0, 0, 0, 0, 1, 0, 1, 0],
    0x1C: [-1, 0, 0, 0, 1, 0, 0, 0, -1],
    0x1F: [0, 1, 0, -1, 0, 0, 0, 0, 1],
    0x20: [0, 0, 1, -1, 0, 0, 0, -1, 0],
    0x22: [0, -1, 0, 0, 0, 1, -1, 0, 0],
    0x23: [0, 0, -1, -1, 0, 0, 0, 1, 0],
  };
}

class _Reader {
  _Reader(this.data);
  final Uint8List data;
  int pos = 0;

  int u8() => data[pos++];

  int u32() {
    final v = data[pos] |
        (data[pos + 1] << 8) |
        (data[pos + 2] << 16) |
        (data[pos + 3] << 24);
    pos += 4;
    return v;
  }

  double f32() {
    final b = ByteData.sublistView(data, pos, pos + 4);
    pos += 4;
    return b.getFloat32(0, Endian.little);
  }

  void skip(int n) => pos += n;

  String str() {
    final len = u32();
    final s = String.fromCharCodes(data.sublist(pos, pos + len));
    pos += len;
    return s;
  }

  /// Byte-column-interleaved unsigned 32-bit ints. Columns arrive
  /// most-significant byte first.
  List<int> interleavedU32(int count) {
    final out = List<int>.filled(count, 0);
    for (var b = 0; b < 4; b++) {
      for (var i = 0; i < count; i++) {
        out[i] = (out[i] << 8) | data[pos++];
      }
    }
    return out;
  }

  List<int> interleavedI32(int count) =>
      interleavedU32(count).map((v) => (v >> 1) ^ -(v & 1)).toList();

  List<int> interleavedI64(int count) {
    final out = List<int>.filled(count, 0);
    for (var b = 0; b < 8; b++) {
      for (var i = 0; i < count; i++) {
        out[i] = (out[i] << 8) | data[pos++];
      }
    }
    return out.map((v) => (v >> 1) ^ -(v & 1)).toList();
  }

  /// Interleaved f32s are byte-interleaved big-endian words rotated right
  /// one bit (Roblox moves the exponent byte to the front).
  List<double> interleavedF32(int count) {
    final raw = interleavedU32(count);
    final bytes = Uint8List(count * 4);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      final v = ((raw[i] >> 1) | (raw[i] << 31)) & 0xFFFFFFFF;
      view.setUint32(i * 4, v, Endian.little);
    }
    return [for (var i = 0; i < count; i++) view.getFloat32(i * 4, Endian.little)];
  }
}
