import 'dart:typed_data';

/// Web browsers transparently handle content-encoded bodies; for file-level
/// gzip payloads (what assetdelivery serves for some rbxm) there is no
/// dart:io on web, so return the bytes as-is.
Uint8List gunzip(Uint8List bytes) => bytes;
