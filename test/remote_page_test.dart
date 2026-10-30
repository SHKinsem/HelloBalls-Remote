import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';
import 'package:helloballs_remote/layout/control_spec.dart';
import 'package:helloballs_remote/pages/remote_page.dart';

import 'robot_link_test.dart' show FakeRobot;

void main() {
  testWidgets('default layout renders every control module', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final layout = RemoteLayout.fromJson(
        jsonDecode(File('assets/layouts/default.json').readAsStringSync()) as Map<String, dynamic>);
    final robot = FakeRobot();
    final link = RobotLink(robot, RemoteModel(RemoteSettings()));
    link.connect(const FoundRobot('AA', 'HelloBalls-1A2B', -50));
    await tester.pump();
    robot.linkStates.add(LinkState.connected);

    await tester.pumpWidget(MaterialApp(home: RemotePage(link: link, layout: layout)));
    await tester.pump();

    for (final label in ['急停', '接管控制', '驾驶', '待机', '吸球', '收球']) {
      expect(find.textContaining(label), findsWidgets, reason: label);
    }
    expect(find.byType(Slider), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Selecting a mode updates the model
    await tester.tap(find.text('待机'));
    await tester.pump();
    expect(link.model.state.value, 0);

    link.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
