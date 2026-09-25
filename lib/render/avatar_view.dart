import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

import 'avatar_painter.dart';
import 'glb_parser.dart';

/// Interactive 3D view of an [AvatarModel]. Drag to orbit, pinch or scroll to
/// zoom, double tap to reset. Spins slowly while idle.
class AvatarView extends StatefulWidget {
  const AvatarView({super.key, required this.model});

  final AvatarModel model;

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView>
    with SingleTickerProviderStateMixin {
  late double _yaw;
  late double _pitch;
  late double _distance;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  DateTime _lastInteraction = DateTime(2000);

  static const _spinSpeed = 0.4; // radians per second
  static const _idleDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _resetCamera();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(AvatarView old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      _resetCamera();
    }
  }

  void _resetCamera() {
    _yaw = 0.4;
    _pitch = 0.15;
    _distance = widget.model.radius * 2.4;
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    if (DateTime.now().difference(_lastInteraction) < _idleDelay) return;
    setState(() {
      _yaw += _spinSpeed * dt.inMicroseconds / Duration.microsecondsPerSecond;
    });
  }

  void _markInteraction() => _lastInteraction = DateTime.now();

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _markInteraction();
    setState(() {
      if (details.scale != 1) {
        _distance = (_distance / details.scale).clamp(
          widget.model.radius * 1.2,
          widget.model.radius * 12,
        );
      }
      _yaw -= details.focalPointDelta.dx * 0.008;
      _pitch = (_pitch + details.focalPointDelta.dy * 0.008)
          .clamp(-1.3, 1.3);
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _markInteraction();
      setState(() {
        _distance = (_distance * math.pow(1.0015, event.scrollDelta.dy))
            .clamp(
          widget.model.radius * 1.2,
          widget.model.radius * 12,
        )
            .toDouble();
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onScaleStart: (_) => _markInteraction(),
        onScaleUpdate: _onScaleUpdate,
        onDoubleTap: () {
          _markInteraction();
          setState(_resetCamera);
        },
        child: CustomPaint(
          painter: AvatarPainter(
            model: widget.model,
            yaw: _yaw,
            pitch: _pitch,
            distance: _distance,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
