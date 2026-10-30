import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/demo_transport.dart';
import 'package:helloballs_remote/ble/protocol.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';

void main() {
  test('demo robot only drives with takeover and honours the e-stop', () {
    fakeAsync((async) {
      final model = RemoteModel(RemoteSettings()..maxWheelRpm = 1000..deadzone = 0..expo = 0);
      final link = RobotLink(DemoTransport(), model);
      link.connect(const FoundRobot('demo', 'demo', -40));
      async.elapse(const Duration(seconds: 1));
      expect(link.connected, isTrue);

      model.setDrive(0, 1);
      async.elapse(const Duration(seconds: 1));
      expect(link.status!.wheel1Rpm, 0); // no takeover yet

      model.setTakeover(true);
      model.setDrive(0, 1);
      async.elapse(const Duration(seconds: 2));
      expect(link.status!.source, ActiveSource.ble);
      expect(link.status!.wheel1Rpm, greaterThan(900));

      link.emergencyStop();
      async.elapse(const Duration(seconds: 2));
      expect(link.status!.estop, isTrue);
      expect(link.status!.wheel1Rpm.abs(), lessThan(50));
      link.disconnect();
      async.flushMicrotasks();
    });
  });

  test('disconnecting from the demo robot completes and stops its timers', () {
    fakeAsync((async) {
      final link = RobotLink(DemoTransport(), RemoteModel(RemoteSettings()));
      link.connect(const FoundRobot('demo', 'demo', -40));
      async.elapse(const Duration(seconds: 1));
      var done = false;
      link.disconnect().then((_) => done = true);
      async.elapse(const Duration(seconds: 1));
      expect(done, isTrue);
      expect(async.periodicTimerCount, 0);
      expect(link.state, LinkState.disconnected);
    });
  });
}
