import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../ble/health.dart';
import 'od_protocol.dart';

/// A part of the robot's object dictionary, simulated for demo mode and tests.
/// It answers SDO frames with the same rules and abort codes as the firmware
/// (components/obj_dict) and simulates the motor debug mode (0x2600).
class DemoOdServer {
  DemoOdServer({required this.remoteInControl}) {
    _build();
  }

  /// True while the app holds takeover and keeps sending control frames.
  final bool Function() remoteInControl;

  final _entries = <String, _Entry>{};
  final _objects = <int, String>{};
  late final String descriptor;
  late final int descriptorCrc;

  // Simulated robot
  final motorSpeed = List<double>.filled(5, 0);
  final motorTarget = List<double>.filled(5, 0);
  final motorEnabled = List<bool>.filled(5, false);
  bool debugMode = false;
  int debugMotor = 0;
  double debugTarget = 0;
  bool debugRun = false;
  double debugApplied = 0;
  int debugCap = 500;
  final tpdoEnabled = List<bool>.filled(4, false);
  final tpdoPeriod = [100, 20, 20, 100];
  final tpdoMap = List<List<int>>.generate(4, (_) => <int>[]);
  final _tpdoSeq = List<int>.filled(4, 0);
  final _tpdoLast = List<int>.filled(4, -100000);
  final _start = clock.now();
  int saves = 0;
  RobotHealth health = const RobotHealth(stageReady, faultSerial); // no host computer in demo mode

  static String _k(int index, int sub) => '$index.$sub';

  void _add(int index, int sub, OdType type, int access, String name,
      {int flags = 0, String? unit, num? lo, num? hi, List<String>? enums, Object? value,
      Object? Function()? get, int Function(Object v)? set}) {
    _entries[_k(index, sub)] = _Entry(index, sub, type, access, lo != null ? flags | flagRange : flags, name,
        unit, lo, hi, enums, value, get, set);
  }

  void _build() {
    _objects.addAll({
      0x1008: '设备名', 0x100A: '固件版本', 0x1010: '保存参数', 0x1011: '恢复默认参数', 0x1021: '字典描述',
      0x1022: '字典校验和', 0x2000: '机器人状态', 0x2001: '诊断', 0x2201: '摩擦轮 1（CAN 1）', 0x2202: '摩擦轮 2（CAN 2）',
      0x2203: '左轮（CAN 3）', 0x2204: '右轮（CAN 4）', 0x2205: '拨球（CAN 5）', 0x2600: '电机调试',
      0x3000: '遥控限幅', 0x3103: 'PID 左轮', 0x5000: '急停',
    });
    _add(0x1008, 0, OdType.str, odRead, '设备名', value: 'HelloBalls-演示');
    _add(0x100A, 0, OdType.str, odRead, '固件版本', value: 'demo');
    _add(0x1010, 1, OdType.u32, odWrite, '保存全部参数', flags: flagIdle | flagConfirm, set: (v) {
      if (v != saveSignature) return 0x06090030;
      saves++;
      return 0;
    });
    _add(0x1011, 1, OdType.u32, odWrite, '恢复默认参数', flags: flagIdle | flagConfirm,
        set: (v) => v == loadSignature ? 0 : 0x06090030);
    _add(0x1021, 0, OdType.domain, odRead, '字典描述', get: () => utf8.encode(descriptor));
    _add(0x1022, 0, OdType.u32, odRead, '字典校验和', get: () => descriptorCrc);
    for (var n = 0; n < 4; n++) {
      _objects[0x1800 + n] = 'TPDO${n + 1} 通信参数';
      _objects[0x1A00 + n] = 'TPDO${n + 1} 映射';
      _add(0x1800 + n, 1, OdType.u16, odRead | odWrite, '周期', unit: 'ms', lo: 10, hi: 5000,
          get: () => tpdoPeriod[n], set: (v) {
        tpdoPeriod[n] = v as int;
        return 0;
      });
      _add(0x1800 + n, 2, OdType.boolean, odRead | odWrite, '启用', get: () => tpdoEnabled[n], set: (v) {
        if (v == true && tpdoMap[n].isEmpty) return 0x08000022;
        tpdoEnabled[n] = v as bool;
        return 0;
      });
      _add(0x1A00 + n, 0, OdType.u8, odRead | odWrite, '映射条数', lo: 0, hi: 8, get: () => tpdoMap[n].length);
      for (var k = 1; k <= 8; k++) {
        _add(0x1A00 + n, k, OdType.u32, odRead | odWrite, '映射 $k',
            get: () => k <= tpdoMap[n].length ? tpdoMap[n][k - 1] : 0);
      }
    }
    _add(0x2000, 1, OdType.u8, odRead, 'MCU 状态', flags: flagPdo,
        enums: ['空闲', '找球中', '已取球', '射球中', '射球完成', '错误'], value: 0);
    _add(0x2000, 4, OdType.boolean, odRead, '急停锁存', flags: flagPdo, value: false);
    _add(0x2000, 6, OdType.u32, odRead, '运行时间', flags: flagPdo, unit: 'ms',
        get: () => clock.now().difference(_start).inMilliseconds);
    _add(0x2001, 1, OdType.u8, odRead, '开机阶段', flags: flagPdo, enums: bootStages, get: () => health.stage);
    _add(0x2001, 2, OdType.u32, odRead, '故障位', flags: flagPdo, get: () => health.faults);
    _add(0x2001, 3, OdType.str, odRead, '故障原因', get: () => health.summary);
    for (var id = 1; id <= 5; id++) {
      final i = id - 1;
      _add(0x2200 + id, 1, OdType.i16, odRead, '实测转速', flags: flagPdo, unit: 'rpm', get: () => motorSpeed[i].round());
      _add(0x2200 + id, 2, OdType.f32, odRead, '目标值', flags: flagPdo, get: () => motorTarget[i]);
      _add(0x2200 + id, 3, OdType.f32, odRead, '电流', flags: flagPdo, unit: 'A', get: () => motorSpeed[i].abs() / 1500);
      _add(0x2200 + id, 4, OdType.f32, odRead, '温度', flags: flagPdo, unit: '°C', get: () => id == 5 ? -1.0 : 31.5);
      _add(0x2200 + id, 7, OdType.boolean, odRead, '使能', flags: flagPdo, get: () => motorEnabled[i]);
      _add(0x2200 + id, 8, OdType.u8, odRead, 'CAN ID', value: id);
    }
    _add(0x2600, 1, OdType.boolean, odRead | odWrite, '调试模式', get: () => debugMode, set: (v) {
      if (v == true && !remoteInControl()) return 0x08000022;
      debugMode = v as bool;
      debugRun = false;
      debugTarget = 0;
      return 0;
    });
    _add(0x2600, 2, OdType.u8, odRead | odWrite, '调试电机', lo: 0, hi: 4,
        enums: ['未选择', '摩擦轮 1', '摩擦轮 2', '左轮', '右轮'], get: () => debugMotor, set: (v) {
      if (v != debugMotor) {
        debugRun = false;
        debugTarget = 0;
      }
      debugMotor = v as int;
      return 0;
    });
    _add(0x2600, 3, OdType.f32, odRead | odWrite, '目标转速', flags: flagPdo, unit: 'rpm', lo: -9000, hi: 9000,
        get: () => debugTarget, set: (v) {
      debugTarget = (v as num).toDouble();
      return 0;
    });
    _add(0x2600, 4, OdType.boolean, odRead | odWrite, '运行（按住）', flags: flagPdo, get: () => debugRun, set: (v) {
      if (v == true && (!debugMode || debugMotor == 0)) return 0x08000022;
      debugRun = v as bool;
      return 0;
    });
    _add(0x2600, 5, OdType.u16, odRead | odWrite, '调试转速上限', flags: flagStore, unit: 'rpm', lo: 0, hi: 9000,
        get: () => debugCap, set: (v) {
      debugCap = v as int;
      return 0;
    });
    _add(0x2600, 6, OdType.f32, odRead, '实际下发转速', flags: flagPdo, unit: 'rpm', get: () => debugApplied);
    _add(0x2600, 7, OdType.i16, odRead, '实测转速', flags: flagPdo, unit: 'rpm',
        get: () => debugMotor == 0 ? 0 : motorSpeed[debugMotor - 1].round());
    _add(0x2600, 8, OdType.f32, odRead, '电流', flags: flagPdo, unit: 'A',
        get: () => debugMotor == 0 ? 0.0 : motorSpeed[debugMotor - 1].abs() / 1500);
    _add(0x2600, 9, OdType.f32, odRead, '温度', flags: flagPdo, unit: '°C', get: () => debugMotor == 0 ? 0.0 : 31.5);
    _add(0x3000, 1, OdType.u16, odRead | odWrite, '遥控轮速上限', flags: flagStore, unit: 'rpm', lo: 0, hi: 9000, value: 3000);
    _add(0x3000, 2, OdType.u16, odRead | odWrite, '遥控摩擦轮上限', flags: flagStore, lo: 0, hi: 9000, value: 6000);
    const pid = ['Kp', 'Ki', 'Kd', 'Kr', 'Km', 'Umax', 'Umin'];
    const pidValues = [25.0, 0.03, 0.5, 0.1, 0.1, 3000.0, -3000.0];
    for (var k = 0; k < 7; k++) {
      _add(0x3103, k + 1, OdType.f32, odRead | odWrite, pid[k], flags: flagStore | flagIdle | flagConfirm,
          lo: k == 6 ? -16384 : 0, hi: k == 6 ? 0 : (k == 5 ? 16384 : (k < 3 ? 10000 : 10)), value: pidValues[k]);
    }
    _add(0x5000, 1, OdType.boolean, odWrite, '急停');
    _add(0x5000, 2, OdType.boolean, odWrite, '解除急停', flags: flagConfirm);

    // Default TPDO mappings, as in the firmware
    tpdoMap[1].addAll([
      pdoMapWord(0x2600, 6, 32), pdoMapWord(0x2600, 7, 16), pdoMapWord(0x2600, 8, 32), pdoMapWord(0x2600, 9, 32),
      pdoMapWord(0x2600, 4, 8),
    ]);
    descriptor = _describe();
    descriptorCrc = crc32(utf8.encode(descriptor));
  }

  String _describe() {
    final keys = _entries.values.toList()..sort((a, b) => (a.index << 8 | a.sub) - (b.index << 8 | b.sub));
    final objects = <Map<String, Object?>>[];
    for (final e in keys) {
      if (objects.isEmpty || objects.last['i'] != e.index) {
        objects.add({'i': e.index, 'n': _objects[e.index] ?? '', 'e': <Map<String, Object?>>[]});
      }
      (objects.last['e'] as List).add({
        's': e.sub,
        'n': e.name,
        't': e.type.code,
        'a': e.access,
        'f': e.flags,
        if (e.unit != null) 'u': e.unit,
        if (e.lo != null) 'lo': e.lo,
        if (e.hi != null) 'hi': e.hi,
        if (e.enums != null) 'en': e.enums,
      });
    }
    return jsonEncode({'v': 1, 'o': objects});
  }

  /// Leaves debug mode when the remote lets go, like the firmware's 10 ms tick, and moves the motors.
  void tick(double dtSeconds) {
    if (debugMode && !remoteInControl()) {
      debugMode = false;
      debugRun = false;
    }
    final run = debugMode && debugRun && debugMotor != 0;
    final goal = run ? debugTarget.clamp(-debugCap.toDouble(), debugCap.toDouble()) : 0.0;
    final step = 1000 * dtSeconds;
    if (!run) {
      debugApplied = 0;
    } else if (goal > debugApplied + step) {
      debugApplied += step;
    } else if (goal < debugApplied - step) {
      debugApplied -= step;
    } else {
      debugApplied = goal;
    }
    for (var i = 0; i < 5; i++) {
      final on = run && debugMotor == i + 1;
      motorEnabled[i] = on;
      motorTarget[i] = on ? debugApplied : 0;
      motorSpeed[i] += (motorTarget[i] - motorSpeed[i]) * (on ? 0.25 : 0.1);
    }
  }

  /// TPDO frames due at [nowMs].
  List<Uint8List> dueTpdos(int nowMs) {
    final out = <Uint8List>[];
    for (var n = 0; n < 4; n++) {
      if (!tpdoEnabled[n] || nowMs - _tpdoLast[n] < tpdoPeriod[n]) continue;
      _tpdoLast[n] = nowMs;
      final b = BytesBuilder()..add([n + 1, _tpdoSeq[n]++ & 0xFF, nowMs & 0xFF, (nowMs >> 8) & 0xFF]);
      for (final w in tpdoMap[n]) {
        final e = _entries[_k(w >> 16, (w >> 8) & 0xFF)]!;
        b.add(e.type.encode(e.read()!));
      }
      out.add(b.toBytes());
    }
    return out;
  }

  /// Answers one SDO request like the firmware's od_sdo_handle().
  Uint8List handle(List<int> raw, {int maxPayload = 244}) {
    if (raw.length < sdoHeader) return Uint8List(0);
    final seq = raw[0], cmd = raw[1], index = raw[2] | (raw[3] << 8), sub = raw[4];
    Uint8List abort(int code) => SdoFrame(seq, sdoAbort, index, sub, OdType.u32.encode(code)).encode();
    if (raw.length != sdoHeader + raw[5]) return abort(0x06070010);
    final data = raw.sublist(sdoHeader);
    final e = _entries[_k(index, sub)];
    final missing = _entries.values.any((x) => x.index == index) ? 0x06090011 : 0x06020000;
    final room = (maxPayload - sdoHeader).clamp(0, 255);

    switch (cmd) {
      case sdoRead:
        if (e == null) return abort(missing);
        if (e.access & odRead == 0) return abort(0x06010001);
        final bytes = e.bytes();
        if (bytes.length > room) return abort(0x06070010);
        return SdoFrame(seq, sdoReadRsp, index, sub, bytes).encode();
      case sdoSegRead:
        if (e == null) return abort(missing);
        if (e.access & odRead == 0) return abort(0x06010001);
        if (data.length != 4) return abort(0x06070010);
        final offset = OdType.u32.decode(data) as int;
        final bytes = e.bytes();
        if (offset > bytes.length) return abort(0x06070010);
        final end = (offset + room - 4).clamp(offset, bytes.length);
        return SdoFrame(seq, sdoSegReadRsp, index, sub, [...OdType.u32.encode(bytes.length), ...bytes.sublist(offset, end)])
            .encode();
      case sdoWrite:
        if (e == null) return abort(missing);
        if (e.access & odWrite == 0) return abort(0x06010002);
        final v = e.type.decode(data);
        if (v == null || data.length != e.type.size) return abort(0x06070010);
        if (e.type == OdType.boolean && data[0] > 1) return abort(0x06090030);
        if (v is num && (v.isNaN || (e.lo != null && (v < e.lo! || v > e.hi!)))) return abort(0x06090030);
        if (e.set != null) {
          final rc = e.set!(v);
          if (rc != 0) return abort(rc);
        } else if (e.get == null) {
          e.value = v;
        } else {
          return abort(0x06010002);
        }
        final echo = e.access & odRead != 0 ? e.bytes() : <int>[];
        return SdoFrame(seq, sdoWriteRsp, index, sub, echo).encode();
      default:
        return abort(0x05030000);
    }
  }
}

class _Entry {
  _Entry(this.index, this.sub, this.type, this.access, this.flags, this.name, this.unit, this.lo, this.hi, this.enums,
      this.value, this.get, this.set);

  final int index, sub;
  final OdType type;
  final int access, flags;
  final String name;
  final String? unit;
  final num? lo, hi;
  final List<String>? enums;
  Object? value;
  final Object? Function()? get;
  final int Function(Object v)? set;

  Object? read() => get != null ? get!() : value;
  List<int> bytes() => type.encode(read() ?? 0);
}

int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (~crc) & 0xFFFFFFFF;
}
