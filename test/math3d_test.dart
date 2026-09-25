import 'package:bin/render/math3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Vec3', () {
    test('arithmetic', () {
      const a = Vec3(1, 2, 3);
      const b = Vec3(4, 5, 6);
      expect(a + b, isA<Vec3>());
      expect((a + b).x, 5);
      expect((a + b).y, 7);
      expect((a + b).z, 9);
      expect((b - a).x, 3);
      expect((a * 2).z, 6);
    });

    test('dot, cross, length, normalize', () {
      const x = Vec3(1, 0, 0);
      const y = Vec3(0, 1, 0);
      expect(x.dot(y), 0);
      final z = x.cross(y);
      expect(z.x, 0);
      expect(z.y, 0);
      expect(z.z, 1);
      expect(const Vec3(3, 4, 0).length, 5);
      expect(const Vec3(3, 4, 0).normalized().length, closeTo(1, 1e-9));
      expect(Vec3.zero.normalized(), Vec3.zero);
    });
  });

  group('Mat4', () {
    test('identity', () {
      final m = Mat4.identity();
      final p = m.transformPoint(const Vec3(1, 2, 3));
      expect(p.x, 1);
      expect(p.y, 2);
      expect(p.z, 3);
    });

    test('translation', () {
      final p =
          Mat4.translation(10, -5, 2).transformPoint(const Vec3(1, 1, 1));
      expect(p.x, 11);
      expect(p.y, -4);
      expect(p.z, 3);
    });

    test('scaling', () {
      final p = Mat4.scaling(2, 3, 4).transformPoint(const Vec3(1, 1, 1));
      expect(p.x, 2);
      expect(p.y, 3);
      expect(p.z, 4);
    });

    test('quaternion rotation', () {
      // 90 degrees around Y: +Z maps to +X
      final m = Mat4.rotationQuaternion(
          0, 0.7071067811865476, 0, 0.7071067811865476);
      final p = m.transformPoint(const Vec3(0, 0, 1));
      expect(p.x, closeTo(1, 1e-6));
      expect(p.y, closeTo(0, 1e-6));
      expect(p.z, closeTo(0, 1e-6));
    });

    test('multiplication chains transforms', () {
      final m = Mat4.translation(5, 0, 0) * Mat4.scaling(2, 2, 2);
      final p = m.transformPoint(const Vec3(1, 0, 0));
      expect(p.x, 7);
    });

    test('perspective divides by w', () {
      final m = Mat4.perspective(1.0, 1.0, 0.1, 100);
      final p = m.transformPoint(const Vec3(0, 0, -1));
      expect(p.x, closeTo(0, 1e-6));
      expect(m.transformW(const Vec3(0, 0, -1)), closeTo(1, 1e-6));
    });

    test('lookAt puts target on -z', () {
      final view = Mat4.lookAt(
          const Vec3(0, 0, 10), Vec3.zero, const Vec3(0, 1, 0));
      final p = view.transformPoint(Vec3.zero);
      expect(p.x, closeTo(0, 1e-6));
      expect(p.y, closeTo(0, 1e-6));
      expect(p.z, closeTo(-10, 1e-6));
    });

    test('fromColumnMajor roundtrip', () {
      final values = List<double>.generate(16, (i) => i.toDouble());
      final m = Mat4.fromColumnMajor(values);
      expect(m.m[15], 15);
    });
  });
}
