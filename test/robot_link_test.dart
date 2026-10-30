import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/protocol.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';

class FakeRobot implements RobotTransport {
  final controls = <ControlFrame>[];
  final actions = <ActionFrame>[];
  final linkStates = StreamController<LinkState>.broadcast();
  final status = StreamController<List<int>>.broadcast();
  bool disconnected = false;

  @override
  Future<String?> ensureReady() async => null;
  @override
  Stream<FoundRobot> scan() => Stream.value(const FoundRobot('AA', 'HelloBalls-1A2B', -50));
  @override
  Stream<LinkState> connect(String id) => linkStates.stream;
  @override
  Future<void> disconnect() async => disconnected = true;
  @override
  Future<void> writeControl(List<int> frame) async => controls.add(ControlFrame.decode(frame)!);
  @override
  Future<void> writeAction(List<int> frame) async => actions.add(ActionFrame.decode(frame)!);
  @override
  Stream<List<int>> statusStream() => status.stream;
  @override
  Future<String> readInfo() async => 'proto=1;fw=test';
}

void main() {
  late FakeRobot robot;
  late RemoteModel model;
  late RobotLink link;

  setUp(() {
    robot = FakeRobot();
    model = RemoteModel(RemoteSettings()..sendHz = 25..maxWheelRpm = 1000..expo = 0..deadzone = 0);
    link = RobotLink(robot, model);
  });

  test('sends control frames at the configured rate once connected', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'HelloBalls-1A2B', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      async.elapse(const Duration(seconds: 1));
      expect(robot.controls.length, inInclusiveRange(24, 25));
      // seq increments, default is drive mode without takeover
      expect(robot.controls[1].seq, (robot.controls[0].seq + 1) & 0xFF);
      expect(robot.controls.last.state, HostState.scanning.value);
      expect(robot.controls.last.flags, 0);
    });
  });

  test('stick, sliders and takeover end up in the frame', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'x', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      model.setTakeover(true);
      model.setDrive(0, 1);
      model.setSlider('tilt', 20);
      async.elapse(const Duration(milliseconds: 100));
      final f = robot.controls.last;
      expect(f.flags & flagTakeover, flagTakeover);
      expect(f.wheel1Rpm, 1000);
      expect(f.wheel2Rpm, 1000);
      expect(f.tiltAngle, 20);
    });
  });

  test('status notifications are decoded', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'x', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      async.flushMicrotasks();
      robot.status.add(const StatusFrame(mcuState: 2, activeSrc: 2, flags: statusTakeover, wheel1Rpm: 990).encode());
      async.flushMicrotasks();
      expect(link.status!.mcuState, 2);
      expect(link.status!.source, ActiveSource.ble);
      expect(link.status!.wheel1Rpm, 990);
      expect(link.info, 'proto=1;fw=test');
    });
  });

  test('disconnect sends a stop frame without takeover and stops the loop', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'x', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      model.setTakeover(true);
      model.setDrive(0.5, 1);
      async.elapse(const Duration(milliseconds: 200));
      link.disconnect();
      async.flushMicrotasks();
      final last = robot.controls.last;
      expect(last.flags, 0);
      expect(last.wheel1Rpm, 0);
      expect(last.wheel2Rpm, 0);
      expect(robot.disconnected, isTrue);
      final n = robot.controls.length;
      async.elapse(const Duration(seconds: 1));
      expect(robot.controls.length, n);
    });
  });

  test('emergency stop sends the action and drops takeover', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'x', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      async.flushMicrotasks();
      model.setTakeover(true);
      link.emergencyStop();
      async.flushMicrotasks();
      expect(robot.actions.single.action, actionEstop);
      expect(model.takeover, isFalse);
    });
  });

  test('link loss stops sending', () {
    fakeAsync((async) {
      link.connect(const FoundRobot('AA', 'x', -50));
      async.flushMicrotasks();
      robot.linkStates.add(LinkState.connected);
      async.elapse(const Duration(milliseconds: 200));
      robot.linkStates.add(LinkState.disconnected);
      async.flushMicrotasks();
      final n = robot.controls.length;
      async.elapse(const Duration(seconds: 1));
      expect(robot.controls.length, n);
      expect(link.error, isNotNull);
    });
  });
}
