import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Kinds of on-screen control modules.
enum ControlType { joystick, slider, button, toggle, status }

/// One control module on the remote screen, loaded from a JSON layout.
///
/// Position and size are fractions of the control area, so a layout works on
/// any landscape screen. [binding] says what the control drives:
///   joystick: "drive"
///   slider:   "tilt" | "shoot"
///   button:   "state:<0-5>" | "action:estop" | "action:clear_estop"
///   toggle:   "takeover"
///   status:   "mcu" | "wheels" | "link"
class ControlSpec {
  ControlSpec({
    required this.id,
    required this.type,
    required this.binding,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.label = '',
    this.min = 0,
    this.max = 1,
    this.step = 1,
    this.initial = 0,
    this.returnToZero = false,
    this.vertical = false,
    this.confirm = false,
    this.color,
  });

  final String id;
  final ControlType type;
  final String binding;
  final double x, y, w, h;
  final String label;
  final double min, max, step, initial;
  final bool returnToZero;
  final bool vertical;
  final bool confirm; // button needs a long press
  final String? color; // "danger" | "primary" | null

  factory ControlSpec.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return ControlSpec(
      id: j['id'] as String,
      type: ControlType.values.byName(j['type'] as String),
      binding: j['binding'] as String,
      x: d('x', 0),
      y: d('y', 0),
      w: d('w', 0.2),
      h: d('h', 0.2),
      label: j['label'] as String? ?? '',
      min: d('min', 0),
      max: d('max', 1),
      step: d('step', 1),
      initial: d('initial', 0),
      returnToZero: j['returnToZero'] as bool? ?? false,
      vertical: j['vertical'] as bool? ?? false,
      confirm: j['confirm'] as bool? ?? false,
      color: j['color'] as String?,
    );
  }
}

class RemoteLayout {
  RemoteLayout(this.name, this.controls);

  final String name;
  final List<ControlSpec> controls;

  factory RemoteLayout.fromJson(Map<String, dynamic> j) => RemoteLayout(
        j['name'] as String? ?? 'layout',
        (j['controls'] as List).map((c) => ControlSpec.fromJson(c as Map<String, dynamic>)).toList(),
      );

  static Future<RemoteLayout> loadAsset([String path = 'assets/layouts/default.json']) async {
    final text = await rootBundle.loadString(path);
    return RemoteLayout.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }
}
