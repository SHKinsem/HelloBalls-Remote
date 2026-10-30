// Checks lib/ble/protocol.dart against the vectors shared with the firmware
// (HelloBalls-2.0: components/ble_remote/test/vectors.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/protocol.dart';

List<int> hex(String s) {
  final h = s.replaceAll(' ', '');
  return [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
}

void main() {
  final vectors = jsonDecode(File('test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

  test('control frames', () {
    for (final v in vectors['control'] as List) {
      final f = v['fields'] as Map<String, dynamic>;
      final frame = ControlFrame(
        seq: f['seq'], state: f['state'], flags: f['flags'], wheel1Rpm: f['wheel1_rpm'],
        wheel2Rpm: f['wheel2_rpm'], tiltAngle: f['tilt_angle'], shootSpeed: f['shoot_speed'],
      );
      expect(frame.encode(), hex(v['hex']));
      final d = ControlFrame.decode(hex(v['hex']))!;
      expect([d.seq, d.state, d.flags, d.wheel1Rpm, d.wheel2Rpm, d.tiltAngle, d.shootSpeed],
          [f['seq'], f['state'], f['flags'], f['wheel1_rpm'], f['wheel2_rpm'], f['tilt_angle'], f['shoot_speed']]);
    }
  });

  test('action frames', () {
    for (final v in vectors['action'] as List) {
      final f = v['fields'] as Map<String, dynamic>;
      expect(ActionFrame(f['action'], f['param']).encode(), hex(v['hex']));
      final d = ActionFrame.decode(hex(v['hex']))!;
      expect([d.action, d.param], [f['action'], f['param']]);
    }
  });

  test('status frames', () {
    for (final v in vectors['status'] as List) {
      final f = v['fields'] as Map<String, dynamic>;
      final d = StatusFrame.decode(hex(v['hex']))!;
      expect([d.mcuState, d.hostState, d.activeSrc, d.flags, d.lastSeq, d.wheel1Rpm, d.wheel2Rpm, d.uptimeMs], [
        f['mcu_state'], f['host_state'], f['active_src'], f['flags'], f['last_seq'],
        f['wheel1_rpm'], f['wheel2_rpm'], f['uptime_ms'],
      ]);
      expect(d.encode(), hex(v['hex']));
    }
  });

  test('invalid frames are rejected', () {
    for (final v in vectors['invalid'] as List) {
      final data = hex(v['hex']);
      final ok = switch (v['kind']) {
        'control' => ControlFrame.decode(data) != null,
        'action' => ActionFrame.decode(data) != null,
        _ => StatusFrame.decode(data) != null,
      };
      expect(ok, isFalse, reason: v['why']);
    }
  });

  test('out-of-range values are clamped, not wrapped', () {
    final d = ControlFrame.decode(const ControlFrame(wheel1Rpm: 40000, wheel2Rpm: -40000).encode())!;
    expect(d.wheel1Rpm, 32767);
    expect(d.wheel2Rpm, -32768);
  });
}
