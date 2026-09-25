import 'dart:math' as math;

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final len = length;
    if (len == 0) return Vec3.zero;
    return Vec3(x / len, y / len, z / len);
  }
}

class Mat4 {
  Mat4._(this.m);

  final List<double> m; // column-major, 16 elements

  static Mat4 identity() =>
      Mat4._([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  static Mat4 fromColumnMajor(List<double> values) {
    assert(values.length == 16);
    return Mat4._(List.of(values));
  }

  static Mat4 translation(double x, double y, double z) =>
      Mat4._([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]);

  static Mat4 scaling(double x, double y, double z) =>
      Mat4._([x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]);

  static Mat4 rotationQuaternion(double qx, double qy, double qz, double qw) {
    final x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
    final xx = qx * x2, xy = qx * y2, xz = qx * z2;
    final yy = qy * y2, yz = qy * z2, zz = qz * z2;
    final wx = qw * x2, wy = qw * y2, wz = qw * z2;
    return Mat4._([
      1 - (yy + zz), xy + wz, xz - wy, 0,
      xy - wz, 1 - (xx + zz), yz + wx, 0,
      xz + wy, yz - wx, 1 - (xx + yy), 0,
      0, 0, 0, 1,
    ]);
  }

  Mat4 operator *(Mat4 o) {
    final out = List<double>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += m[k * 4 + r] * o.m[c * 4 + k];
        }
        out[c * 4 + r] = sum;
      }
    }
    return Mat4._(out);
  }

  Vec3 transformPoint(Vec3 p) {
    final x = m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12];
    final y = m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13];
    final z = m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14];
    final w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];
    if (w != 0 && w != 1) return Vec3(x / w, y / w, z / w);
    return Vec3(x, y, z);
  }

  double transformW(Vec3 p) =>
      m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];

  static Mat4 perspective(double fovY, double aspect, double near, double far) {
    final f = 1 / math.tan(fovY / 2);
    final nf = 1 / (near - far);
    return Mat4._([
      f / aspect, 0, 0, 0,
      0, f, 0, 0,
      0, 0, (far + near) * nf, -1,
      0, 0, 2 * far * near * nf, 0,
    ]);
  }

  static Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final z = (eye - target).normalized();
    final x = up.cross(z).normalized();
    final y = z.cross(x);
    return Mat4._([
      x.x, y.x, z.x, 0,
      x.y, y.y, z.y, 0,
      x.z, y.z, z.z, 0,
      -x.dot(eye), -y.dot(eye), -z.dot(eye), 1,
    ]);
  }
}
