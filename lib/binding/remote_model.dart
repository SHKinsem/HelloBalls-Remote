import 'package:flutter/foundation.dart';

import '../ble/protocol.dart';
import '../layout/control_spec.dart';
import 'drive_mixer.dart';
import 'remote_settings.dart';

/// Holds the value of every control and turns them into a control frame.
/// Controls only report normalised values here; bindings decide what they mean.
class RemoteModel extends ChangeNotifier {
  RemoteModel(this.settings);

  final RemoteSettings settings;

  double driveX = 0;
  double driveY = 0;
  final Map<String, double> sliders = {};
  bool takeover = false;
  HostState state = HostState.scanning;

  void initFromLayout(RemoteLayout layout) {
    for (final c in layout.controls) {
      if (c.type == ControlType.slider) {
        sliders.putIfAbsent(c.binding, () => c.initial);
      }
    }
  }

  void setDrive(double x, double y) {
    driveX = x;
    driveY = y;
    notifyListeners();
  }

  void setSlider(String binding, double value) {
    sliders[binding] = value;
    notifyListeners();
  }

  void setTakeover(bool on) {
    takeover = on;
    notifyListeners();
  }

  void setState(HostState s) {
    state = s;
    notifyListeners();
  }

  /// Back to a safe default: no takeover, sticks centred, friction wheels off.
  void reset() {
    takeover = false;
    driveX = 0;
    driveY = 0;
    sliders.updateAll((k, v) => k == 'shoot' ? 0 : v);
    state = HostState.scanning;
    notifyListeners();
  }

  ControlFrame buildFrame(int seq) {
    final x = shapeAxis(driveX, deadzone: settings.deadzone, expo: settings.expo);
    var y = shapeAxis(driveY, deadzone: settings.deadzone, expo: settings.expo);
    if (settings.invertForward) y = -y;
    var (w1, w2) = mixDifferential(x, y, maxRpm: settings.maxWheelRpm);
    if (settings.swapWheels) (w1, w2) = (w2, w1);
    return ControlFrame(
      seq: seq,
      state: state.value,
      flags: takeover ? flagTakeover : 0,
      wheel1Rpm: w1,
      wheel2Rpm: w2,
      tiltAngle: (sliders['tilt'] ?? 0).round(),
      shootSpeed: (sliders['shoot'] ?? 0).round(),
    );
  }
}
