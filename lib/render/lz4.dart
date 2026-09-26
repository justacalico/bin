import 'dart:typed_data';

/// Decompresses an LZ4 block (the framing Roblox uses for RBXM chunks).
Uint8List lz4Decompress(Uint8List src, int expectedSize) {
  final out = Uint8List(expectedSize);
  var ip = 0;
  var op = 0;
  while (ip < src.length) {
    final token = src[ip++];
    var litLen = token >> 4;
    if (litLen == 15) {
      int b;
      do {
        b = src[ip++];
        litLen += b;
      } while (b == 255);
    }
    for (var i = 0; i < litLen; i++) {
      out[op++] = src[ip++];
    }
    if (ip >= src.length) break;
    final offset = src[ip] | (src[ip + 1] << 8);
    ip += 2;
    var matchLen = token & 0xF;
    if (matchLen == 15) {
      int b;
      do {
        b = src[ip++];
        matchLen += b;
      } while (b == 255);
    }
    matchLen += 4;
    var ref = op - offset;
    for (var i = 0; i < matchLen; i++) {
      out[op++] = out[ref++];
    }
  }
  return out;
}
