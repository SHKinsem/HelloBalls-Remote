// Boot stage and fault bits, mirrors the firmware's main/health.h
// (HelloBalls-2.0). Seen in the scan response before connecting, and in
// object 0x2001 once connected.
import 'dart:typed_data';

const List<String> bootStages = [
  '启动中', '启动蓝牙', '初始化 IMU', '启动 CAN 电机', '初始化舵机', '初始化步进电机', '步进回零', '启动串口', '就绪', //
];
const int stageReady = 8;

const int faultImu = 1 << 0;
const int faultCan = 1 << 1;
int faultMotor(int canId) => 1 << (1 + canId);
const int faultHoming = 1 << 7;
const int faultSerial = 1 << 8;
const int faultEstop = 1 << 9;

const _motorNames = ['摩擦轮 1', '摩擦轮 2', '左轮', '右轮', '拨球'];

class RobotHealth {
  const RobotHealth(this.stage, this.faults);

  final int stage;
  final int faults;

  bool get ready => stage == stageReady;

  /// Faults other than "no serial host", which is normal when only the phone drives.
  bool get hasProblem => !ready || faults & ~faultSerial != 0;

  String get stageText => stage < bootStages.length ? bootStages[stage] : '阶段 $stage';

  List<String> get faultTexts => [
        if (faults & faultImu != 0) 'IMU 无响应',
        if (faults & faultCan != 0) 'CAN 驱动没有启动',
        for (var id = 1; id <= 5; id++)
          if (faults & faultMotor(id) != 0) '${_motorNames[id - 1]}（CAN $id）无反馈',
        if (faults & faultHoming != 0) '步进回零超时，限位开关没有触发',
        if (faults & faultSerial != 0) '上位机串口没有数据',
        if (faults & faultEstop != 0) '急停中',
      ];

  /// One line for the scan list and the header.
  String get summary => [if (!ready) '正在$stageText', ...faultTexts].join('；').ifEmpty('正常');

  /// From the scan response's manufacturer data: company 0xFFFF | 'H' 'B' | version 1 | stage | faults u32 LE.
  static RobotHealth? fromManufacturerData(List<int> d) {
    if (d.length < 10 || d[0] != 0xFF || d[1] != 0xFF || d[2] != 0x48 || d[3] != 0x42 || d[4] != 1) return null;
    final faults = ByteData.sublistView(Uint8List.fromList(d), 6, 10).getUint32(0, Endian.little);
    return RobotHealth(d[5], faults);
  }

  List<int> toManufacturerData() =>
      [0xFF, 0xFF, 0x48, 0x42, 1, stage, faults & 0xFF, (faults >> 8) & 0xFF, (faults >> 16) & 0xFF, (faults >> 24) & 0xFF];

  @override
  bool operator ==(Object other) => other is RobotHealth && other.stage == stage && other.faults == faults;
  @override
  int get hashCode => Object.hash(stage, faults);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
