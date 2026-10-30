import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/robot_link.dart';
import 'ble/robot_transport.dart';
import 'binding/remote_model.dart';
import 'binding/remote_settings.dart';
import 'layout/control_spec.dart';
import 'od/od_cache.dart';
import 'pages/scan_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  final settings = RemoteSettings();
  await settings.load();
  final layout = await RemoteLayout.loadAsset();
  final link = RobotLink(ReactiveBleTransport(), RemoteModel(settings), odCache: PrefsOdCache());

  runApp(HelloBallsRemoteApp(link: link, layout: layout));
}

class HelloBallsRemoteApp extends StatelessWidget {
  const HelloBallsRemoteApp({super.key, required this.link, required this.layout});

  final RobotLink link;
  final RemoteLayout layout;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HelloBalls 遥控器',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7CB342), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF7CB342), brightness: Brightness.dark, useMaterial3: true),
      home: ScanPage(link: link, layout: layout, autoDemo: const bool.fromEnvironment('DEMO')),
    );
  }
}
