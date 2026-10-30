import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/demo_transport.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';
import 'package:helloballs_remote/pages/dictionary_page.dart';
import 'package:helloballs_remote/pages/motor_debug_page.dart';

Future<(RobotLink, DemoTransport)> _connect(WidgetTester tester) async {
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final transport = DemoTransport();
  final link = RobotLink(transport, RemoteModel(RemoteSettings()));
  link.connect(const FoundRobot('demo', 'demo', -40));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 100));
  expect(link.od, isNotNull);
  return (link, transport);
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('motor debug page runs the chosen motor only while held', (tester) async {
    final (link, transport) = await _connect(tester);
    await tester.pumpWidget(MaterialApp(home: MotorDebugPage(link: link)));
    await _settle(tester);
    expect(transport.od.debugMode, isTrue);

    await tester.tap(find.text('右轮'));
    await _settle(tester, 300);
    expect(transport.od.debugMotor, 4);

    // switching motors drops the target on both sides
    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await _settle(tester, 300);
    await tester.tap(find.text('左轮'));
    await _settle(tester, 300);
    expect(transport.od.debugTarget, 0);
    expect(find.text('目标 0 rpm'), findsOneWidget);
    await tester.tap(find.text('右轮'));
    await _settle(tester, 300);

    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await _settle(tester, 300);
    expect(transport.od.debugTarget, greaterThan(0));

    await tester.ensureVisible(find.text('按住运行'));
    await tester.pump();
    final hold = await tester.startGesture(tester.getCenter(find.text('按住运行')));
    await _settle(tester, 1000);
    expect(transport.od.debugRun, isTrue);
    expect(transport.od.motorSpeed[3], greaterThan(10));
    await hold.up();
    await _settle(tester, 300);
    expect(transport.od.debugRun, isFalse);

    // a release still stops the motor when telemetry already showed it stopped
    final quick = await tester.startGesture(tester.getCenter(find.text('按住运行')));
    transport.od.debugRun = false; // as if a TPDO raced the run=1 write
    await quick.up();
    await _settle(tester, 300);
    expect(transport.od.debugRun, isFalse);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 500);
    expect(transport.od.debugMode, isFalse);
    expect(link.model.takeover, isFalse);
    link.disconnect(); // completes only as fake time advances
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('dictionary page lists objects and writes a checked value', (tester) async {
    final (link, transport) = await _connect(tester);
    await tester.pumpWidget(MaterialApp(home: DictionaryPage(link: link)));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('电机调试'), 200);
    await tester.ensureVisible(find.text('电机调试'));
    await tester.pump();

    await tester.tap(find.text('电机调试'));
    await _settle(tester, 1000);
    await tester.scrollUntilVisible(find.text('调试转速上限'), 200);
    await tester.ensureVisible(find.text('调试转速上限'));
    await tester.pump();
    await tester.tap(find.text('调试转速上限'));
    await _settle(tester, 300);
    await tester.enterText(find.byType(TextField), '99999');
    await tester.tap(find.text('写入'));
    await tester.pump();
    expect(find.textContaining('范围'), findsWidgets); // rejected before sending
    await tester.enterText(find.byType(TextField), '800');
    await tester.tap(find.text('写入'));
    await _settle(tester, 500);
    expect(transport.od.debugCap, 800);

    link.disconnect(); // completes only as fake time advances
    await tester.pump(const Duration(seconds: 5));
  });
}
