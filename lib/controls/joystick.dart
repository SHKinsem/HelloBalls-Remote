import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Two-axis stick. Reports x (right +) and y (up/forward +) in [-1, 1] and
/// springs back to the centre on release.
class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.onChanged, this.label = ''});

  final void Function(double x, double y) onChanged;
  final String label;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero; // normalised, |_knob| <= 1

  void _update(Offset local, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final centre = size.center(Offset.zero);
    var v = (local - centre) / r;
    if (v.distance > 1) v = v / v.distance;
    setState(() => _knob = v);
    widget.onChanged(v.dx, -v.dy);
  }

  void _release() {
    setState(() => _knob = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final r = math.min(size.width, size.height) / 2;
      final knobR = r * 0.32;
      return GestureDetector(
        onPanStart: (d) => _update(d.localPosition, size),
        onPanUpdate: (d) => _update(d.localPosition, size),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: CustomPaint(
          size: size,
          painter: _StickPainter(
            knob: _knob,
            radius: r,
            knobRadius: knobR,
            base: scheme.surfaceContainerHighest,
            ring: scheme.outline,
            knobColor: scheme.primary,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
        ),
      );
    });
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({
    required this.knob,
    required this.radius,
    required this.knobRadius,
    required this.base,
    required this.ring,
    required this.knobColor,
  });

  final Offset knob;
  final double radius, knobRadius;
  final Color base, ring, knobColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, radius - 2, Paint()..color = base);
    canvas.drawCircle(c, radius - 2, Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    final cross = Paint()
      ..color = ring.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(c - Offset(radius * 0.8, 0), c + Offset(radius * 0.8, 0), cross);
    canvas.drawLine(c - Offset(0, radius * 0.8), c + Offset(0, radius * 0.8), cross);
    final travel = radius - knobRadius;
    canvas.drawCircle(c + knob * travel, knobRadius, Paint()..color = knobColor);
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.knob != knob || old.knobColor != knobColor;
}
