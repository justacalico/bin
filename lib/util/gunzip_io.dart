import 'dart:io';
import 'dart:typed_data';

/// Inflate a gzip-wrapped file when the payload itself is gzipped
/// (magic 1f 8b). Anything else passes through.
Uint8List gunzip(Uint8List bytes) {
  if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    return Uint8List.fromList(gzip.decode(bytes));
  }
  return bytes;
}
