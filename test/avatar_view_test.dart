import 'package:bin/render/avatar_painter.dart';
import 'package:bin/render/avatar_view.dart';
import 'package:bin/render/glb_parser.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<AvatarModel> _model(WidgetTester tester) async {
  AvatarModel? model;
  await tester.runAsync(() async {
    model = await GlbParser().parse(buildTestGlb());
  });
  return model!;
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 300, child: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders model with painter', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('auto-rotates while idle', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drag orbits the camera', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump();
    await tester.drag(
        find.byType(AvatarView), const Offset(60, 20));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('pinch zooms', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump();

    final center = tester.getCenter(find.byType(AvatarView));
    final f1 = await tester.startGesture(center + const Offset(-20, 0));
    final f2 = await tester.startGesture(center + const Offset(20, 0));
    await f1.moveBy(const Offset(-40, 0));
    await f2.moveBy(const Offset(40, 0));
    await tester.pump();
    await f1.up();
    await f2.up();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('scroll zooms', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump();

    final scroll = TestPointer(1, PointerDeviceKind.mouse);
    scroll.hover(tester.getCenter(find.byType(AvatarView)));
    await tester.sendEventToBinding(
        scroll.scroll(const Offset(0, -120)));
    await tester.pump();
  });

  testWidgets('double tap resets camera', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump();
    await tester.drag(find.byType(AvatarView), const Offset(80, 0));
    await tester.pump();
    await tester.tap(find.byType(AvatarView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(AvatarView));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('swapping model resets camera', (tester) async {
    final model = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model)));
    await tester.pump();
    final model2 = await _model(tester);
    await tester.pumpWidget(_app(AvatarView(model: model2)));
    await tester.pump();
  });

  testWidgets('painter repaints on param change', (tester) async {
    final model = await _model(tester);
    final a = AvatarPainter(model: model, yaw: 0, pitch: 0, distance: 10);
    final b = AvatarPainter(model: model, yaw: 1, pitch: 0, distance: 10);
    final c = AvatarPainter(model: model, yaw: 1, pitch: 0.5, distance: 10);
    final d = AvatarPainter(model: model, yaw: 1, pitch: 0.5, distance: 20);
    expect(a.shouldRepaint(b), isTrue);
    expect(b.shouldRepaint(c), isTrue);
    expect(c.shouldRepaint(d), isTrue);
    expect(d.shouldRepaint(d), isFalse);
    final model2 = await _model(tester);
    final e = AvatarPainter(model: model2, yaw: 1, pitch: 0.5, distance: 20);
    expect(d.shouldRepaint(e), isTrue);
  });

  testWidgets('painter handles edge views', (tester) async {
    final model = await _model(tester);
    for (final yaw in [0.0, 1.5, 3.14, -1.0]) {
      await tester.pumpWidget(_app(CustomPaint(
        painter: AvatarPainter(model: model, yaw: yaw, pitch: 1.2, distance: 3),
        child: const SizedBox.expand(),
      )));
      await tester.pump();
    }
  });

  testWidgets('painter draws untextured-only model', (tester) async {
    final base = await _model(tester);
    final untextured = AvatarModel(
      parts: base.parts,
      materials: [AvatarMaterial(color: const Color(0xFF4488CC))],
      center: base.center,
      radius: base.radius,
      minY: base.minY,
    );
    await tester.pumpWidget(_app(CustomPaint(
      painter: AvatarPainter(model: untextured, yaw: 0.3, pitch: 0.2, distance: 8),
      child: const SizedBox.expand(),
    )));
    await tester.pump();
  });
}
