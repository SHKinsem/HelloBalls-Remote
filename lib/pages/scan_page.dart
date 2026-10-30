import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/demo_transport.dart';
import '../ble/robot_link.dart';
import '../ble/robot_transport.dart';
import '../layout/control_spec.dart';
import 'remote_page.dart';

/// Lists nearby HelloBalls robots (filtered by the remote service UUID).
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.link, required this.layout, this.autoDemo = false});

  final RobotLink link;
  final RemoteLayout layout;
  final bool autoDemo; // open the simulated robot straight away

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final Map<String, FoundRobot> _found = {};
  StreamSubscription<FoundRobot>? _scan;
  String? _message;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDemo());
    } else {
      _startScan();
    }
  }

  @override
  void dispose() {
    _scan?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _scan?.cancel();
    setState(() {
      _found.clear();
      _message = null;
      _scanning = true;
    });
    final problem = await widget.link.transport.ensureReady();
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _message = problem;
        _scanning = false;
      });
      return;
    }
    _scan = widget.link.transport.scan().listen(
      (r) => setState(() {
        // the health bytes are in the scan response, which not every report carries
        final health = r.health ?? _found[r.id]?.health;
        _found[r.id] = FoundRobot(r.id, r.name, r.rssi, health);
      }),
      onError: (Object e) => setState(() {
        _message = '扫描失败：$e';
        _scanning = false;
      }),
    );
    // Stop after a while to save battery; the user can scan again.
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _scanning) {
        _scan?.cancel();
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _open(FoundRobot r) async {
    await _scan?.cancel();
    setState(() => _scanning = false);
    await widget.link.connect(r);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemotePage(link: widget.link, layout: widget.layout),
    ));
  }

  /// Try the remote against a simulated robot, no hardware needed.
  Future<void> _openDemo() async {
    await _scan?.cancel();
    setState(() => _scanning = false);
    final demo = RobotLink(DemoTransport(), widget.link.model);
    await demo.connect(const FoundRobot('demo', 'HelloBalls-演示', -40));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemotePage(link: demo, layout: widget.layout),
    ));
    await demo.disconnect();
    demo.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final robots = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(
        title: const Text('HelloBalls 遥控器'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: const Text('演示模式'),
            onPressed: _openDemo,
          ),
          IconButton(
            icon: _scanning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: Column(children: [
        if (_message != null)
          MaterialBanner(content: Text(_message!), actions: [
            TextButton(onPressed: _startScan, child: const Text('重试')),
          ]),
        Expanded(
          child: robots.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/branding/app_icon.png', width: 72, height: 72),
                    ),
                    const SizedBox(height: 16),
                    Text(_scanning ? '正在寻找附近的机器人…' : '没有找到机器人，确认机器人已上电后点右上角重新扫描'),
                  ]),
                )
              : ListView(children: [
                  for (final r in robots)
                    ListTile(
                      leading: const Icon(Icons.sports_tennis),
                      title: Text(r.name),
                      subtitle: Text.rich(TextSpan(children: [
                        TextSpan(text: '${r.id}  信号 ${r.rssi} dBm'),
                        if (r.health != null)
                          TextSpan(
                            text: '\n${r.health!.summary}',
                            style: TextStyle(
                                color: r.health!.hasProblem ? Theme.of(context).colorScheme.error : const Color(0xFF43A047)),
                          ),
                      ])),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(r),
                    ),
                ]),
        ),
      ]),
    );
  }
}
