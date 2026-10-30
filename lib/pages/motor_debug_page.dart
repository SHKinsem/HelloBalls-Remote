import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/protocol.dart';
import '../ble/robot_link.dart';
import '../od/od_client.dart';
import '../od/od_dictionary.dart';

const int _debug = 0x2600;
const int _debugPdo = 2;

/// Runs one registered motor at a chosen speed (0x2600). The robot only allows
/// it while this app has taken over, the robot is idle and not e-stopped; the
/// motor turns only while the run button is held.
class MotorDebugPage extends StatefulWidget {
  const MotorDebugPage({super.key, required this.link});

  final RobotLink link;

  @override
  State<MotorDebugPage> createState() => _MotorDebugPageState();
}

class _MotorDebugPageState extends State<MotorDebugPage> {
  OdClient? _od;
  OdEntry? _motorEntry;
  String? _error;
  bool _ready = false;
  bool _running = false;
  bool _held = false;

  int _motor = 0;
  int _cap = 500;
  double _target = 0;
  double? _sentTarget;
  bool _sendingTarget = false;

  double _applied = 0;
  int _speed = 0;
  double _current = 0;
  double _temperature = 0;
  final _history = <({double applied, double speed})>[];
  StreamSubscription<TpdoValues>? _tpdoSub;

  RobotLink get link => widget.link;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  Future<void> _enter() async {
    // The firmware needs takeover and idle in the control stream before it accepts debug mode
    link.model.reset();
    link.model.setTakeover(true);
    link.model.setState(HostState.idle);
    try {
      final dict = await link.loadDictionary();
      final od = _od = link.od!;
      _motorEntry = dict.entry(_debug, 2);
      await _enterDebugMode(od);
      _motor = await od.read(_debug, 2) as int;
      _cap = await od.read(_debug, 5) as int;
      _tpdoSub = od.tpdoStream.where((v) => v.pdo == _debugPdo).listen(_onTpdo);
      await od.enableTpdo(_debugPdo, periodMs: 50);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _enterDebugMode(OdClient od) async {
    for (var attempt = 0;; attempt++) {
      try {
        await od.write(_debug, 1, true);
        return;
      } on OdException catch (e) {
        // the first control frames with takeover may not have reached the robot yet
        if (e.code != 0x08000022 || attempt >= 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  void _leave() {
    _tpdoSub?.cancel();
    final od = _od;
    if (od != null && link.od == od) {
      od.write(_debug, 4, false).catchError((Object _) => null);
      od.write(_debug, 1, false).catchError((Object _) => null);
      od.disableTpdo(_debugPdo).catchError((Object _) {});
    }
    // after the route is gone: the remote page listens to the model
    scheduleMicrotask(link.model.reset);
  }

  void _onTpdo(TpdoValues v) {
    if (!mounted) return;
    setState(() {
      _applied = (v.values[odKey(_debug, 6)] as num?)?.toDouble() ?? _applied;
      _speed = (v.values[odKey(_debug, 7)] as int?) ?? _speed;
      _current = (v.values[odKey(_debug, 8)] as num?)?.toDouble() ?? _current;
      _temperature = (v.values[odKey(_debug, 9)] as num?)?.toDouble() ?? _temperature;
      final run = v.values[odKey(_debug, 4)];
      if (run is bool && !run && _running) _running = false; // the robot stopped it
      _history.add((applied: _applied, speed: _speed.toDouble()));
      if (_history.length > 200) _history.removeAt(0);
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _write(int sub, Object value) async {
    try {
      await _od!.write(_debug, sub, value);
    } catch (e) {
      if (mounted) _snack('$e');
      rethrow;
    }
  }

  Future<void> _selectMotor(int m) async {
    if (_running) return;
    try {
      await _write(2, m);
      setState(() {
        if (m != _motor) {
          // the robot zeroes the target when the motor changes
          _target = 0;
          _sentTarget = 0;
        }
        _motor = m;
        _history.clear();
      });
    } catch (_) {}
  }

  Future<void> _editCap() async {
    final controller = TextEditingController(text: '$_cap');
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('调试转速上限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'rpm', helperText: '目标转速会被限制在 ±上限 之内'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(controller.text.trim())), child: const Text('确定')),
        ],
      ),
    );
    if (v == null) return;
    try {
      await _write(5, v);
      setState(() {
        _cap = v;
        _target = _target.clamp(-_cap.toDouble(), _cap.toDouble());
      });
      _sendTarget();
    } catch (_) {}
  }

  /// Sends the latest target; slider moves during a write are folded into the next one.
  Future<void> _sendTarget() async {
    if (_sendingTarget || _od == null) return;
    _sendingTarget = true;
    try {
      while (_sentTarget != _target) {
        final t = _target;
        await _od!.write(_debug, 3, t);
        _sentTarget = t;
      }
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      _sendingTarget = false;
    }
  }

  /// Follows the finger, not the telemetry: a release always sends run=0, even
  /// when a TPDO already showed the motor stopped (the queued run=1 may still land).
  Future<void> _setRun(bool on) async {
    if (on && _held) return;
    _held = on;
    setState(() => _running = on);
    try {
      await _write(4, on);
    } catch (_) {
      if (mounted && on) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('电机调试（速度模式）'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: () {
                _setRun(false);
                link.emergencyStop();
              },
              icon: const Icon(Icons.stop_circle),
              label: const Text('急停'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('进不了调试模式：$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('需要机器人在线、未急停，并且没有其他人在控制。', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _enter();
                    },
                    child: const Text('重试'),
                  ),
                ]),
              ),
            )
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 5, child: _controls(theme)),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: _readout(theme)),
                  ]),
                ),
    );
  }

  Widget _controls(ThemeData theme) {
    final names = _motorEntry?.enums ?? const ['未选择', '摩擦轮 1', '摩擦轮 2', '左轮', '右轮'];
    return ListView(children: [
      SegmentedButton<int>(
        segments: [for (var i = 1; i < names.length; i++) ButtonSegment(value: i, label: Text(names[i]))],
        selected: {if (_motor > 0) _motor},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        onSelectionChanged: _running ? null : (s) => s.isEmpty ? null : _selectMotor(s.first),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text('目标 ${_target.round()} rpm', style: theme.textTheme.titleMedium),
        TextButton(
          onPressed: () {
            setState(() => _target = 0);
            _sendTarget();
          },
          child: const Text('归零'),
        ),
        const Spacer(),
        TextButton.icon(onPressed: _running ? null : _editCap, icon: const Icon(Icons.speed), label: Text('上限 ±$_cap')),
      ]),
      Slider(
        value: _target.clamp(-_cap.toDouble(), _cap.toDouble()),
        min: -_cap.toDouble(),
        max: math.max(_cap.toDouble(), 1),
        divisions: _cap > 0 ? (_cap * 2 ~/ 10).clamp(1, 400) : null,
        label: '${_target.round()}',
        onChanged: _cap == 0
            ? null
            : (v) {
                setState(() => _target = v);
                _sendTarget();
              },
      ),
      const SizedBox(height: 8),
      _HoldButton(
        enabled: _motor > 0,
        running: _running,
        onChanged: _setRun,
      ),
      const SizedBox(height: 8),
      Text(
        _motor == 0 ? '先选一个电机' : '按住才转，松手立即停。离开本页会自动退出调试。',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    ]);
  }

  Widget _readout(ThemeData theme) {
    Widget value(String label, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(v, style: theme.textTheme.titleMedium),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      value('下发转速', '${_applied.round()} rpm'),
      value('实测转速', '$_speed rpm'),
      value('电流', '${_current.toStringAsFixed(2)} A'),
      value('温度', '${_temperature.toStringAsFixed(1)} °C'),
      const SizedBox(height: 12),
      Expanded(
        child: CustomPaint(
          painter: _SpeedChart(
            _history,
            applied: theme.colorScheme.primary,
            speed: theme.colorScheme.tertiary,
            grid: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _legend(theme.colorScheme.primary, '下发'),
        const SizedBox(width: 16),
        _legend(theme.colorScheme.tertiary, '实测'),
      ]),
    ]);
  }

  Widget _legend(Color c, String label) =>
      Row(children: [Container(width: 12, height: 3, color: c), const SizedBox(width: 4), Text(label)]);
}

class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.enabled, required this.running, required this.onChanged});

  final bool enabled;
  final bool running;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.colorScheme.surfaceContainerHighest
        : running
            ? const Color(0xFF43A047)
            : theme.colorScheme.primaryContainer;
    return Listener(
      onPointerDown: enabled ? (_) => onChanged(true) : null,
      onPointerUp: enabled ? (_) => onChanged(false) : null,
      onPointerCancel: enabled ? (_) => onChanged(false) : null,
      child: Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Text(running ? '运行中…（松手停止）' : '按住运行',
            style: theme.textTheme.titleLarge?.copyWith(color: running ? Colors.white : null)),
      ),
    );
  }
}

/// Applied and measured speed over the last few seconds.
class _SpeedChart extends CustomPainter {
  _SpeedChart(this.points, {required this.applied, required this.speed, required this.grid});

  final List<({double applied, double speed})> points;
  final Color applied;
  final Color speed;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);
    canvas.drawRect(Offset.zero & size, gridPaint..style = PaintingStyle.stroke);
    if (points.length < 2) return;
    var top = 100.0;
    for (final p in points) {
      top = math.max(top, math.max(p.applied.abs(), p.speed.abs()));
    }
    void line(double Function(({double applied, double speed})) pick, Color c) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x = size.width * i / 199;
        final y = size.height / 2 - pick(points[i]) / top * size.height / 2;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    line((p) => p.applied, applied);
    line((p) => p.speed, speed);
  }

  @override
  bool shouldRepaint(_SpeedChart old) => true;
}
