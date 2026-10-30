import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/demo_transport.dart';
import 'package:helloballs_remote/ble/health.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';

void main() {
  test('manufacturer data from the scan response', () {
    // stage 6 (homing), faults: homing timeout + left wheel (CAN 3) silent
    final d = [0xFF, 0xFF, 0x48, 0x42, 1, 6, 0x10, 0x00, 0x00, 0x00];
    final h = RobotHealth.fromManufacturerData([...d.sublist(0, 6), 0x90, 0, 0, 0])!;
    expect(h.stage, 6);
    expect(h.faults, faultHoming | faultMotor(3));
    expect(h.summary, '正在步进回零；左轮（CAN 3）无反馈；步进回零超时，限位开关没有触发');
    expect(h.hasProblem, isTrue);
    expect(RobotHealth.fromManufacturerData(h.toManufacturerData()), h);
    expect(RobotHealth.fromManufacturerData([0x4C, 0x00, 1, 2, 3, 4, 5, 6, 7, 8]), isNull); // someone else's data
    expect(RobotHealth.fromManufacturerData(d.sublist(0, 8)), isNull);
  });

  test('no serial host alone is not a problem', () {
    expect(const RobotHealth(stageReady, faultSerial).hasProblem, isFalse);
    expect(const RobotHealth(stageReady, 0).summary, '正常');
  });

  test('the link polls diagnostics while connected', () {
    fakeAsync((async) {
      final transport = DemoTransport();
      final link = RobotLink(transport, RemoteModel(RemoteSettings()));
      link.connect(FoundRobot('demo', 'demo', -40, transport.od.health));
      async.elapse(const Duration(seconds: 2));
      expect(link.health, transport.od.health);
      expect(link.healthReason, '上位机串口没有数据');

      transport.od.health = RobotHealth(stageReady, faultHoming | faultSerial);
      async.elapse(const Duration(seconds: 2));
      expect(link.health!.faults & faultHoming, isNot(0));
      expect(link.healthReason, contains('回零超时'));
      link.disconnect();
      async.elapse(const Duration(seconds: 1));
    });
  });
}
