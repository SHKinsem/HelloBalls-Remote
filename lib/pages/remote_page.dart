import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/protocol.dart';
import '../ble/robot_link.dart';
import '../ble/robot_transport.dart';
import '../binding/remote_model.dart';
import '../controls/joystick.dart';
import '../controls/simple_controls.dart';
import '../layout/control_spec.dart';
import 'settings_page.dart';

/// The remote screen: every control module of the layout, placed by fraction.
class RemotePage extends StatefulWidget {
  const RemotePage({super.key, required this.link, required this.layout});

  final RobotLink link;
  final RemoteLayout layout;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  RobotLink get link => widget.link;
  RemoteModel get model => widget.link.model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.initFromLayout(widget.layout);
    // Full screen: the system bars would take a fifth of a landscape phone
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never keep driving from the background: release control and disconnect.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      link.disconnect();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _leave() async {
    await link.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([link, model]),
            builder: (context, _) => Column(children: [
              _buildHeader(context),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  return Stack(children: [
                    for (final spec in widget.layout.controls)
                      Positioned(
                        left: spec.x * c.maxWidth,
                        top: spec.y * c.maxHeight,
                        width: spec.w * c.maxWidth,
                        height: spec.h * c.maxHeight,
                        child: Padding(padding: const EdgeInsets.all(3), child: _buildControl(spec)),
                      ),
                  ]);
                }),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One slim row: disconnect, robot name, live status, settings and the
  /// emergency stop, which is always there whatever the layout says.
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final link = _linkStatus();
    final st = this.link.status;
    final dim = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(icon: const Icon(Icons.link_off), tooltip: '断开', onPressed: _leave),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Text(this.link.robotName ?? '机器人', style: theme.textTheme.titleSmall),
              const SizedBox(width: 16),
              Icon(Icons.circle, size: 10, color: link.warn ? theme.colorScheme.error : const Color(0xFF43A047)),
              const SizedBox(width: 6),
              Text(link.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, color: link.warn ? theme.colorScheme.error : null)),
              const SizedBox(width: 20),
              Text('机器人 ', style: dim),
              Text(_mcuText(st), style: theme.textTheme.bodyMedium),
              const SizedBox(width: 20),
              Text('轮速 ', style: dim),
              Text(_wheelsText(st), style: theme.textTheme.bodyMedium),
            ]),
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.tune),
          tooltip: '设置',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettingsPage(settings: model.settings, onChanged: this.link.restartTicker),
          )),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: SizedBox(
            width: 150,
            child: RemoteButton(label: '急停', danger: true, onPressed: this.link.connected ? this.link.emergencyStop : null),
          ),
        ),
      ]),
    );
  }

  ({String text, bool warn}) _linkStatus() {
    final st = link.status;
    if (link.state == LinkState.connecting) return (text: '连接中…', warn: false);
    if (!link.connected) return (text: link.error ?? '未连接', warn: true);
    if (st == null || !link.statusFresh) return (text: '已连接，无状态回报', warn: true);
    if (st.estop) return (text: '急停中', warn: true);
    return (
      text: switch (st.source) {
        ActiveSource.ble => '遥控器在控制',
        ActiveSource.serial => '上位机在控制',
        ActiveSource.none => model.takeover ? '接管中…' : '无人控制',
      },
      warn: false,
    );
  }

  String _mcuText(StatusFrame? st) =>
      st == null ? '-' : '${st.mcuLabel} / ${HostState.fromValue(st.hostState).label}';

  String _wheelsText(StatusFrame? st) => st == null ? '-' : '${st.wheel1Rpm} / ${st.wheel2Rpm} rpm';

  Widget _buildControl(ControlSpec spec) {
    final enabled = link.connected;
    switch (spec.type) {
      case ControlType.joystick:
        return Joystick(label: spec.label, onChanged: model.setDrive);

      case ControlType.slider:
        return RemoteSlider(
          label: spec.label,
          value: model.sliders[spec.binding] ?? spec.initial,
          min: spec.min,
          max: spec.max,
          step: spec.step,
          vertical: spec.vertical,
          returnToZero: spec.returnToZero,
          onChanged: (v) => model.setSlider(spec.binding, v),
        );

      case ControlType.toggle:
        return RemoteToggle(
          label: spec.label,
          value: model.takeover,
          onChanged: enabled ? model.setTakeover : null,
        );

      case ControlType.button:
        return _buildButton(spec, enabled);

      case ControlType.status:
        return _buildStatus(spec);
    }
  }

  Widget _buildButton(ControlSpec spec, bool enabled) {
    final b = spec.binding;
    if (b.startsWith('state:')) {
      final s = HostState.fromValue(int.parse(b.substring(6)));
      return RemoteButton(
        label: spec.label,
        selected: model.state == s,
        confirm: spec.confirm,
        onPressed: enabled ? () => model.setState(s) : null,
      );
    }
    final VoidCallback? action = switch (b) {
      'action:estop' => link.emergencyStop,
      'action:clear_estop' => () => link.sendAction(actionClearEstop),
      _ => null,
    };
    return RemoteButton(
      label: spec.label,
      danger: spec.color == 'danger',
      confirm: spec.confirm,
      onPressed: enabled ? action : null,
    );
  }

  Widget _buildStatus(ControlSpec spec) {
    final st = link.status;
    switch (spec.binding) {
      case 'link':
        final l = _linkStatus();
        return StatusTile(label: spec.label, value: l.text, warn: l.warn);
      case 'mcu':
        return StatusTile(label: spec.label, value: _mcuText(st));
      case 'wheels':
        return StatusTile(label: spec.label, value: _wheelsText(st));
      default:
        return StatusTile(label: spec.label, value: '?');
    }
  }
}
