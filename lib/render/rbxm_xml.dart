import 'rbxm.dart';

/// Tiny recursive reader for the XML .rbxmx format that assetdelivery serves
/// for older catalog items. Only the property shapes the avatar pipeline
/// needs are decoded; unknown tags are skipped structurally.
class RbxmXmlReader {
  String _s = '';
  int _pos = 0;
  int _nextReferent = 1;

  List<RbxmInstance> read(String source) {
    _s = source;
    _pos = 0;
    final roots = <RbxmInstance>[];
    while (true) {
      _skipTo('<Item');
      if (_pos >= _s.length) break;
      final inst = _readItem();
      if (inst == null) break;
      roots.add(inst);
    }
    return roots;
  }

  void _skipTo(String needle) {
    final i = _s.indexOf(needle, _pos);
    _pos = i < 0 ? _s.length : i;
  }

  /// Reads text up to `</tag>` and moves past it.
  String _textUntil(String closeTag) {
    final i = _s.indexOf(closeTag, _pos);
    if (i < 0) {
      final t = _s.substring(_pos);
      _pos = _s.length;
      return t;
    }
    final t = _s.substring(_pos, i);
    _pos = i + closeTag.length;
    return _unescape(t);
  }

  String _unescape(String v) => v
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');

  static final _itemOpen = RegExp(r'<Item\s+class="([^"]+)"[^>]*>');
  static final _propOpen = RegExp(r'<(\w+)\s*([^>]*)>');

  /// _pos is at `<Item`; consumes through its matching `</Item>`.
  RbxmInstance? _readItem() {
    final open = _itemOpen.firstMatch(_s.substring(_pos));
    if (open == null || open.start != 0) return null;
    _pos += open.end;
    final inst = RbxmInstance(open.group(1)!, _nextReferent++);

    while (_pos < _s.length) {
      final lt = _s.indexOf('<', _pos);
      if (lt < 0) return inst;
      _pos = lt;
      if (_s.startsWith('</Item>', _pos)) {
        _pos += 7;
        return inst;
      }
      if (_s.startsWith('</', _pos)) {
        final end = _s.indexOf('>', _pos);
        if (end < 0) return inst;
        _pos = end + 1;
        continue;
      }
      final m = _propOpen.firstMatch(_s.substring(_pos));
      if (m == null) return null;
      _pos += m.end;
      final tag = m.group(1)!;
      final attrs = m.group(2)!;
      if (tag == 'Item') {
        // nested item: rewind and recurse
        _pos -= m.end;
        final child = _readItem();
        if (child == null) return inst;
        inst.children.add(child);
        continue;
      }
      if (tag == 'Properties') continue; // transparent container
      _readProp(inst, tag, attrs);
    }
    return inst;
  }

  void _readProp(RbxmInstance inst, String tag, String attrs) {
    final nameM = RegExp(r'name="([^"]+)"').firstMatch(attrs);
    final name = nameM?.group(1) ?? '';
    final closeTag = '</$tag>';
    // self-closing or non-property element
    if (name.isEmpty || attrs.endsWith('/')) {
      if (attrs.endsWith('/')) return;
      _pos += _textUntil(closeTag).length;
      return;
    }
    switch (tag) {
      case 'string':
      case 'ProtectedString':
        inst.props[name] = _textUntil(closeTag);
      case 'int':
      case 'token':
        inst.props[name] =
            int.tryParse(_textUntil(closeTag).trim()) ?? 0;
      case 'bool':
        inst.props[name] = _textUntil(closeTag).trim() == 'true';
      case 'float':
      case 'double':
        inst.props[name] =
            double.tryParse(_textUntil(closeTag).trim()) ?? 0.0;
      case 'Vector3':
      case 'CoordinateFrame':
      case 'Color3':
        inst.props[name] = _readNumbers(tag, closeTag);
      case 'Content':
        final body = _textUntil(closeTag);
        final url = RegExp(r'<url>([^<]*)</url>').firstMatch(body);
        if (url != null) inst.props[name] = url.group(1)!.trim();
      default:
        _textUntil(closeTag);
    }
  }

  List<double> _readNumbers(String tag, String closeTag) {
    final body = _textUntil(closeTag);
    final keys = tag == 'CoordinateFrame'
        ? const [
            'X', 'Y', 'Z', 'R00', 'R01', 'R02', 'R10', 'R11', 'R12', 'R20',
            'R21', 'R22'
          ]
        : tag == 'Color3'
            ? const ['R', 'G', 'B']
            : const ['X', 'Y', 'Z'];
    return keys.map((k) {
      final m = RegExp('<$k>([^<]*)</$k>').firstMatch(body);
      return double.tryParse(m?.group(1)?.trim() ?? '') ?? 0.0;
    }).toList();
  }
}
