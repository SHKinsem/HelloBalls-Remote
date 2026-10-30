import 'package:flutter/material.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        appBar: AppBar(
          toolbarHeight: 40,
          title: Text(link.robotName ?? '机器人', style: const TextStyle(fontSize: 16)),
          leading: IconButton(icon: const Icon(Icons.link_off), tooltip: '断开', onPressed: _leave),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '设置',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsPage(settings: model.settings, onChanged: link.restartTicker),
              )),
            ),
          ],
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([link, model]),
            builder: (context, _) => LayoutBuilder(builder: (context, c) {
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
        ),
      ),
    );
  }

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
        final String text;
        var warn = false;
        if (link.state == LinkState.connecting) {
          text = '连接中…';
        } else if (!link.connected) {
          text = link.error ?? '未连接';
          warn = true;
        } else if (st == null || !link.statusFresh) {
          text = '已连接，无状态回报';
          warn = true;
        } else if (st.estop) {
          text = '急停中';
          warn = true;
        } else {
          final src = switch (st.source) {
            ActiveSource.ble => '遥控器在控制',
            ActiveSource.serial => '上位机在控制',
            ActiveSource.none => model.takeover ? '接管中…' : '无人控制',
          };
          text = src;
        }
        return StatusTile(label: spec.label, value: text, warn: warn);
      case 'mcu':
        return StatusTile(
          label: spec.label,
          value: st == null ? '-' : '${st.mcuLabel} / ${HostState.fromValue(st.hostState).label}',
        );
      case 'wheels':
        return StatusTile(label: spec.label, value: st == null ? '-' : '${st.wheel1Rpm} / ${st.wheel2Rpm} rpm');
      default:
        return StatusTile(label: spec.label, value: '?');
    }
  }
}
