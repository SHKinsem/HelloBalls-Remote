import 'dart:math' as math;

/// Shapes a raw stick axis: dead zone around the centre, then an expo curve.
/// [expo] 0 is linear, 1 is fully cubic (fine control near the centre).
double shapeAxis(double v, {double deadzone = 0.08, double expo = 0.3}) {
  final a = v.abs().clamp(0.0, 1.0);
  if (a <= deadzone) return 0;
  final scaled = (a - deadzone) / (1 - deadzone);
  final curved = (1 - expo) * scaled + expo * scaled * scaled * scaled;
  return v.isNegative ? -curved : curved;
}

/// Differential drive mix. x: right positive, y: forward positive, both in [-1, 1].
/// Returns (wheel1, wheel2) motor RPM, scaled so neither exceeds [maxRpm].
(int, int) mixDifferential(double x, double y, {required int maxRpm}) {
  var left = y + x;
  var right = y - x;
  final m = math.max(1.0, math.max(left.abs(), right.abs()));
  left /= m;
  right /= m;
  return ((left * maxRpm).round(), (right * maxRpm).round());
}
