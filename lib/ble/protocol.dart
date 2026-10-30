// HelloBalls BLE remote protocol, mirrors the firmware's ble_remote_codec.c
// (HelloBalls-2.0: components/ble_remote). Both sides are checked against
// test/vectors.json, copied from components/ble_remote/test/vectors.json.
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

const int protocolVersion = 1;

const int controlLen = 12;
const int actionLen = 4;
const int statusLen = 14;

final Uuid serviceUuid = Uuid.parse('b5f90001-7a4c-4e57-9c1d-48a7a3b4c0de');
final Uuid controlUuid = Uuid.parse('b5f90002-7a4c-4e57-9c1d-48a7a3b4c0de');
final Uuid actionUuid = Uuid.parse('b5f90003-7a4c-4e57-9c1d-48a7a3b4c0de');
final Uuid statusUuid = Uuid.parse('b5f90004-7a4c-4e57-9c1d-48a7a3b4c0de');
final Uuid infoUuid = Uuid.parse('b5f90005-7a4c-4e57-9c1d-48a7a3b4c0de');

/// Control frame flags.
const int flagTakeover = 0x01;

/// Action ids.
const int actionEstop = 0x01;
const int actionClearEstop = 0x02;

/// Status flags.
const int statusEstop = 0x01;
const int statusTakeover = 0x02;

/// Host states understood by the firmware state machine (host_state_t).
enum HostState {
  idle(0, '待机'),
  searchingBall(1, '吸球'),
  ballReached(2, '收球'),
  shooting(3, '发射'),
  scanning(4, '驾驶'),
  error(5, '错误');

  const HostState(this.value, this.label);
  final int value;
  final String label;

  static HostState fromValue(int v) =>
      HostState.values.firstWhere((s) => s.value == v, orElse: () => HostState.idle);
}

/// What the MCU reports back (mcu_state_t).
const List<String> mcuStateLabels = ['空闲', '找球中', '已收球', '发射中', '发射完成', '错误'];

/// Command source reported in the status frame.
enum ActiveSource { none, serial, ble }

int _clamp16(int v) => v.clamp(-32768, 32767);

class ControlFrame {
  const ControlFrame({
    this.seq = 0,
    this.state = 0,
    this.flags = 0,
    this.wheel1Rpm = 0,
    this.wheel2Rpm = 0,
    this.tiltAngle = 0,
    this.shootSpeed = 0,
  });

  final int seq;
  final int state;
  final int flags;
  final int wheel1Rpm;
  final int wheel2Rpm;
  final int tiltAngle;
  final int shootSpeed;

  Uint8List encode() {
    final b = ByteData(controlLen);
    b.setUint8(0, protocolVersion);
    b.setUint8(1, seq & 0xFF);
    b.setUint8(2, state & 0xFF);
    b.setUint8(3, flags & 0xFF);
    b.setInt16(4, _clamp16(wheel1Rpm), Endian.little);
    b.setInt16(6, _clamp16(wheel2Rpm), Endian.little);
    b.setInt16(8, _clamp16(tiltAngle), Endian.little);
    b.setInt16(10, _clamp16(shootSpeed), Endian.little);
    return b.buffer.asUint8List();
  }

  static ControlFrame? decode(List<int> data) {
    if (data.length != controlLen || data[0] != protocolVersion) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return ControlFrame(
      seq: b.getUint8(1),
      state: b.getUint8(2),
      flags: b.getUint8(3),
      wheel1Rpm: b.getInt16(4, Endian.little),
      wheel2Rpm: b.getInt16(6, Endian.little),
      tiltAngle: b.getInt16(8, Endian.little),
      shootSpeed: b.getInt16(10, Endian.little),
    );
  }
}

class ActionFrame {
  const ActionFrame(this.action, [this.param = 0]);

  final int action;
  final int param;

  Uint8List encode() {
    final b = ByteData(actionLen);
    b.setUint8(0, protocolVersion);
    b.setUint8(1, action & 0xFF);
    b.setInt16(2, _clamp16(param), Endian.little);
    return b.buffer.asUint8List();
  }

  static ActionFrame? decode(List<int> data) {
    if (data.length != actionLen || data[0] != protocolVersion) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return ActionFrame(b.getUint8(1), b.getInt16(2, Endian.little));
  }
}

class StatusFrame {
  const StatusFrame({
    this.mcuState = 0,
    this.hostState = 0,
    this.activeSrc = 0,
    this.flags = 0,
    this.lastSeq = 0,
    this.wheel1Rpm = 0,
    this.wheel2Rpm = 0,
    this.uptimeMs = 0,
  });

  final int mcuState;
  final int hostState;
  final int activeSrc;
  final int flags;
  final int lastSeq;
  final int wheel1Rpm;
  final int wheel2Rpm;
  final int uptimeMs;

  bool get estop => flags & statusEstop != 0;
  bool get takeover => flags & statusTakeover != 0;
  ActiveSource get source =>
      activeSrc < ActiveSource.values.length ? ActiveSource.values[activeSrc] : ActiveSource.none;
  String get mcuLabel => mcuState < mcuStateLabels.length ? mcuStateLabels[mcuState] : '未知($mcuState)';

  Uint8List encode() {
    final b = ByteData(statusLen);
    b.setUint8(0, protocolVersion);
    b.setUint8(1, mcuState);
    b.setUint8(2, hostState);
    b.setUint8(3, activeSrc);
    b.setUint8(4, flags);
    b.setUint8(5, lastSeq);
    b.setInt16(6, _clamp16(wheel1Rpm), Endian.little);
    b.setInt16(8, _clamp16(wheel2Rpm), Endian.little);
    b.setUint32(10, uptimeMs, Endian.little);
    return b.buffer.asUint8List();
  }

  static StatusFrame? decode(List<int> data) {
    if (data.length != statusLen || data[0] != protocolVersion) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return StatusFrame(
      mcuState: b.getUint8(1),
      hostState: b.getUint8(2),
      activeSrc: b.getUint8(3),
      flags: b.getUint8(4),
      lastSeq: b.getUint8(5),
      wheel1Rpm: b.getInt16(6, Endian.little),
      wheel2Rpm: b.getInt16(8, Endian.little),
      uptimeMs: b.getUint32(10, Endian.little),
    );
  }
}
