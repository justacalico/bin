import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glb_parser.dart';
import 'math3d.dart';

/// Software 3D renderer for an [AvatarModel]. Triangles are transformed to
/// screen space, flat shaded against a fixed key light, depth sorted and
/// drawn with [Canvas.drawVertices]. Textures use an [ui.ImageShader].
class AvatarPainter extends CustomPainter {
  AvatarPainter({
    required this.model,
    required this.yaw,
    required this.pitch,
    required this.distance,
  });

  final AvatarModel model;
  final double yaw;
  final double pitch;
  final double distance;

  static final _lightDir = const Vec3(-0.45, 0.9, 0.55).normalized();

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    final center = model.center;
    final eye = center +
        Vec3(
          math.sin(yaw) * math.cos(pitch),
          math.sin(pitch),
          math.cos(yaw) * math.cos(pitch),
        ) *
            distance;

    final view = Mat4.lookAt(eye, center, const Vec3(0, 1, 0));
    final aspect = size.width / size.height;
    final proj = Mat4.perspective(
      50 * math.pi / 180,
      aspect,
      distance * 0.02,
      distance * 20,
    );
    final viewProj = proj * view;

    _drawShadow(canvas, size, view, viewProj);
    _drawModel(canvas, size, view, viewProj);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        rect.longestSide / 1.4,
        const [Color(0xFF1B1B28), Color(0xFF0A0A12)],
      );
    canvas.drawRect(rect, bg);
  }

  void _drawShadow(Canvas canvas, Size size, Mat4 view, Mat4 viewProj) {
    final ground = Vec3(model.center.x, model.minY, model.center.z);
    final clip = viewProj.transformPoint(ground);
    final w = viewProj.transformW(ground);
    if (w <= 0) return;
    final sx = (clip.x + 1) / 2 * size.width;
    final sy = (1 - clip.y) / 2 * size.height;

    // Perspective scale factor for the shadow radius.
    final edge =
        viewProj.transformPoint(ground + Vec3(model.radius * 0.85, 0, 0));
    final ex = (edge.x + 1) / 2 * size.width;
    final r = (ex - sx).abs();
    if (r <= 0) return;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(sx, sy),
        r,
        const [Color(0x66000000), Color(0x00000000)],
      );
    canvas.save();
    canvas.translate(sx, sy);
    canvas.scale(1, 0.32);
    canvas.drawCircle(Offset.zero, r, paint);
    canvas.restore();
  }

  void _drawModel(Canvas canvas, Size size, Mat4 view, Mat4 viewProj) {
    final tris = <_ScreenTri>[];

    for (var partIndex = 0; partIndex < model.parts.length; partIndex++) {
      final part = model.parts[partIndex];
      final count = part.indices.length;
      for (var i = 0; i + 2 < count; i += 3) {
        final a = part.vertices[part.indices[i]];
        final b = part.vertices[part.indices[i + 1]];
        final c = part.vertices[part.indices[i + 2]];

        final pa = Vec3(a.x, a.y, a.z);
        final pb = Vec3(b.x, b.y, b.z);
        final pc = Vec3(c.x, c.y, c.z);

        final normal = (pb - pa).cross(pc - pa).normalized();

        final depth = _projectDepth(view, pa, pb, pc);
        if (depth == null) continue;

        final sa = _project(viewProj, pa, size);
        final sb = _project(viewProj, pb, size);
        final sc = _project(viewProj, pc, size);
        if (sa == null || sb == null || sc == null) continue;

        final shade = (0.45 + 0.55 * math.max(0.0, normal.dot(_lightDir).abs()))
            .clamp(0.25, 1.0);

        tris.add(_ScreenTri(
          material: part.material.clamp(0, model.materials.length - 1),
          depth: depth,
          pts: [sa, sb, sc],
          uvs: [Offset(a.u, a.v), Offset(b.u, b.v), Offset(c.u, c.v)],
          shade: shade.toDouble(),
        ));
      }
    }

    // Painter's algorithm: farther triangles first.
    tris.sort((t1, t2) => t1.depth.compareTo(t2.depth));

    var start = 0;
    while (start < tris.length) {
      var end = start + 1;
      final material = tris[start].material;
      while (end < tris.length && tris[end].material == material) {
        end++;
      }
      _drawBatch(canvas, tris.sublist(start, end), material);
      start = end;
    }
  }

  double? _projectDepth(Mat4 view, Vec3 a, Vec3 b, Vec3 c) {
    final za = view.transformPoint(a).z;
    final zb = view.transformPoint(b).z;
    final zc = view.transformPoint(c).z;
    if (za >= 0 || zb >= 0 || zc >= 0) return null;
    return za + zb + zc;
  }

  Offset? _project(Mat4 viewProj, Vec3 p, Size size) {
    final w = viewProj.transformW(p);
    if (w <= 0.001) return null;
    final clip = viewProj.transformPoint(p);
    return Offset(
      (clip.x + 1) / 2 * size.width,
      (1 - clip.y) / 2 * size.height,
    );
  }

  void _drawBatch(Canvas canvas, List<_ScreenTri> tris, int materialIndex) {
    final material = model.materials[materialIndex];
    final positions = <Offset>[];
    final colors = <Color>[];
    final texCoords =
        material.image != null ? <Offset>[] : null;

    final img = material.image;
    for (final tri in tris) {
      for (var v = 0; v < 3; v++) {
        positions.add(tri.pts[v]);
        // texture coordinates are in image pixel space, not normalized
        if (texCoords != null && img != null) {
          texCoords.add(Offset(
              tri.uvs[v].dx * img.width, tri.uvs[v].dy * img.height));
        }
        colors.add(material.image != null
            ? _gray(tri.shade)
            : _shade(material.color, tri.shade));
      }
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      colors: colors,
    );
    final paint = Paint();
    if (material.image != null) {
      paint.shader = ui.ImageShader(
        material.image!,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
    }
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
  }

  static Color _shade(Color base, double shade) => Color.from(
        alpha: base.a,
        red: base.r * shade,
        green: base.g * shade,
        blue: base.b * shade,
      );

  static Color _gray(double shade) => Color.from(
        alpha: 1,
        red: shade,
        green: shade,
        blue: shade,
      );

  @override
  bool shouldRepaint(AvatarPainter old) =>
      yaw != old.yaw ||
      pitch != old.pitch ||
      distance != old.distance ||
      model != old.model;
}

class _ScreenTri {
  const _ScreenTri({
    required this.material,
    required this.depth,
    required this.pts,
    required this.uvs,
    required this.shade,
  });

  final int material;
  final double depth;
  final List<Offset> pts;
  final List<Offset> uvs;
  final double shade;
}
