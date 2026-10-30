import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable settings, persisted on the phone.
class RemoteSettings extends ChangeNotifier {
  int maxWheelRpm = 1500; // firmware clamps again (CONFIG_HELLOBALLS_BLE_MAX_WHEEL_RPM)
  int sendHz = 25;
  double deadzone = 0.08;
  double expo = 0.3;
  bool swapWheels = false;
  bool invertForward = false;

  static const _kMaxRpm = 'maxWheelRpm';
  static const _kHz = 'sendHz';
  static const _kDeadzone = 'deadzone';
  static const _kExpo = 'expo';
  static const _kSwap = 'swapWheels';
  static const _kInvert = 'invertForward';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    maxWheelRpm = p.getInt(_kMaxRpm) ?? maxWheelRpm;
    sendHz = p.getInt(_kHz) ?? sendHz;
    deadzone = p.getDouble(_kDeadzone) ?? deadzone;
    expo = p.getDouble(_kExpo) ?? expo;
    swapWheels = p.getBool(_kSwap) ?? swapWheels;
    invertForward = p.getBool(_kInvert) ?? invertForward;
    notifyListeners();
  }

  Future<void> update(void Function(RemoteSettings s) change) async {
    change(this);
    sendHz = sendHz.clamp(10, 50);
    maxWheelRpm = maxWheelRpm.clamp(0, 9000);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMaxRpm, maxWheelRpm);
    await p.setInt(_kHz, sendHz);
    await p.setDouble(_kDeadzone, deadzone);
    await p.setDouble(_kExpo, expo);
    await p.setBool(_kSwap, swapWheels);
    await p.setBool(_kInvert, invertForward);
  }
}
