import 'glb_parser.dart' show MeshVertex;
import 'math3d.dart';

/// Axis-aligned box with optional per-face UV rectangles (normalized 0-1,
/// v measured from the top of the texture).
/// Face keys: px, nx, py, ny, pz, nz.
(List<MeshVertex>, List<int>) boxMesh(
  Vec3 center,
  Vec3 size, {
  Map<String, (double, double, double, double)>? faceUvs,
}) {
  final hx = size.x / 2, hy = size.y / 2, hz = size.z / 2;
  final uv = faceUvs ?? const <String, (double, double, double, double)>{};
  const def = (0.0, 0.0, 1.0, 1.0);

  // each face: 4 corners (x, y, z, u, v where u,v map rect l,t,r,b)
  final verts = <MeshVertex>[];
  final idx = <int>[];
  void face(String name, List<List<double>> corners, List<double> normal) {
    final (l, t, r, b) = uv[name] ?? def;
    final base = verts.length;
    final uvs = [(l, t), (r, t), (r, b), (l, b)];
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      verts.add(MeshVertex(c[0], c[1], c[2], uvs[i].$1, uvs[i].$2));
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  final x0 = center.x - hx, x1 = center.x + hx;
  final y0 = center.y - hy, y1 = center.y + hy;
  final z0 = center.z - hz, z1 = center.z + hz;
  face('px', [[x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1]], [1, 0, 0]);
  face('nx', [[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]], [-1, 0, 0]);
  face('py', [[x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0]], [0, 1, 0]);
  face('ny', [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]], [0, -1, 0]);
  face('pz', [[x1, y0, z1], [x0, y0, z1], [x0, y1, z1], [x1, y1, z1]], [0, 0, 1]);
  face('nz', [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]], [0, 0, -1]);
  return (verts, idx);
}

/// Textured quad on one plane (used for the face decal).
(List<MeshVertex>, List<int>) quadMesh(
    Vec3 center, Vec3 normal, double w, double h) {
  // basis vectors perpendicular to normal
  final n = normal.normalized();
  final right = n.cross(const Vec3(0, 1, 0)).length < 0.01
      ? const Vec3(1, 0, 0)
      : n.cross(const Vec3(0, 1, 0)).normalized();
  final up = right.cross(n).normalized();
  final hw = right * (w / 2);
  final hh = up * (h / 2);
  final verts = [
    MeshVertex(
        (center - hw - hh).x, (center - hw - hh).y, (center - hw - hh).z, 0, 1),
    MeshVertex(
        (center + hw - hh).x, (center + hw - hh).y, (center + hw - hh).z, 1, 1),
    MeshVertex(
        (center + hw + hh).x, (center + hw + hh).y, (center + hw + hh).z, 1, 0),
    MeshVertex(
        (center - hw + hh).x, (center - hw + hh).y, (center - hw + hh).z, 0, 0),
  ];
  return (verts, [0, 1, 2, 0, 2, 3]);
}

/// Rounded box approximating the classic Roblox head: a cube whose surface
/// points are pushed onto a rounded-box distance field.
(List<MeshVertex>, List<int>) roundedBoxMesh(Vec3 center, Vec3 size, double r,
    {int seg = 5}) {
  final hx = size.x / 2, hy = size.y / 2, hz = size.z / 2;
  final ix = hx - r, iy = hy - r, iz = hz - r;
  final verts = <MeshVertex>[];
  final idx = <int>[];

  Vec3 round(Vec3 p) {
    final cx = p.x.clamp(-ix, ix).toDouble();
    final cy = p.y.clamp(-iy, iy).toDouble();
    final cz = p.z.clamp(-iz, iz).toDouble();
    final d = Vec3(p.x - cx, p.y - cy, p.z - cz);
    final len = d.length;
    final n = len < 1e-9 ? Vec3(p.x, p.y, p.z).normalized() : d * (1 / len);
    return Vec3(cx, cy, cz) + n * r + center;
  }

  // 6 cube faces as grids
  final faces = <(int, List<Vec3>)>[
    (0, [Vec3(hx, 0, 0), Vec3(0, -hy, 0), Vec3(0, 0, -hz)]),
    (0, [Vec3(-hx, 0, 0), Vec3(0, -hy, 0), Vec3(0, 0, hz)]),
    (0, [Vec3(0, hy, 0), Vec3(hx, 0, 0), Vec3(0, 0, hz)]),
    (0, [Vec3(0, -hy, 0), Vec3(-hx, 0, 0), Vec3(0, 0, hz)]),
    (0, [Vec3(0, 0, hz), Vec3(-hx, 0, 0), Vec3(0, -hy, 0)]),
    (0, [Vec3(0, 0, -hz), Vec3(hx, 0, 0), Vec3(0, -hy, 0)]),
  ];
  for (final (_, def) in faces) {
    final o = def[0], a = def[1], b = def[2];
    final base = verts.length;
    for (var i = 0; i <= seg; i++) {
      for (var j = 0; j <= seg; j++) {
        final p = o + a * (i / seg) + b * (j / seg);
        final q = round(p);
        verts.add(MeshVertex(q.x, q.y, q.z, i / seg, j / seg));
      }
    }
    for (var i = 0; i < seg; i++) {
      for (var j = 0; j < seg; j++) {
        final r0 = base + i * (seg + 1) + j;
        final r1 = r0 + seg + 1;
        idx.addAll([r0, r0 + 1, r1, r0 + 1, r1 + 1, r1]);
      }
    }
  }
  return (verts, idx);
}

/// Transform a vertex list by a column-major 4x4 matrix.
List<MeshVertex> transformVerts(List<MeshVertex> verts, Mat4 m) => [
      for (final v in verts)
        () {
          final p = m.transformPoint(Vec3(v.x, v.y, v.z));
          return MeshVertex(p.x, p.y, p.z, v.u, v.v);
        }()
    ];

Mat4 cframeMat(List<double> cf) {
  // cf = [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22]
  // Column-major matrix with the rotation basis as columns.
  return Mat4.fromColumnMajor([
    cf[3], cf[6], cf[9], 0,
    cf[4], cf[7], cf[10], 0,
    cf[5], cf[8], cf[11], 0,
    cf[0], cf[1], cf[2], 1,
  ]);
}

/// Rigid-body inverse (rotation transpose, negated translation).
Mat4 rigidInverse(Mat4 m) {
  final c = m.m;
  final rx = [c[0], c[4], c[8], c[1], c[5], c[9], c[2], c[6], c[10]];
  final t = Vec3(c[12], c[13], c[14]);
  final nt = Vec3(
    -(rx[0] * t.x + rx[1] * t.y + rx[2] * t.z),
    -(rx[3] * t.x + rx[4] * t.y + rx[5] * t.z),
    -(rx[6] * t.x + rx[7] * t.y + rx[8] * t.z),
  );
  return Mat4.fromColumnMajor([
    rx[0], rx[3], rx[6], 0,
    rx[1], rx[4], rx[7], 0,
    rx[2], rx[5], rx[8], 0,
    nt.x, nt.y, nt.z, 1,
  ]);
}
