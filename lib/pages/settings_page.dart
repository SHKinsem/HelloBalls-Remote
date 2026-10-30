import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ble/protocol.dart';

import '../binding/remote_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings, this.onChanged});

  final RemoteSettings settings;
  final VoidCallback? onChanged;

  Future<void> _set(void Function(RemoteSettings s) change) async {
    await settings.update(change);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _sliderTile('最大轮速（电机轴 RPM）', settings.maxWheelRpm.toDouble(), 0, 9000, 90,
                (v) => _set((s) => s.maxWheelRpm = v.round()), '${settings.maxWheelRpm}'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('固件还会再限幅一次（默认 3000），以固件为准。', style: TextStyle(fontSize: 12)),
            ),
            _sliderTile('发送频率（Hz）', settings.sendHz.toDouble(), 10, 50, 40,
                (v) => _set((s) => s.sendHz = v.round()), '${settings.sendHz}'),
            _sliderTile('摇杆死区', settings.deadzone, 0, 0.3, 30, (v) => _set((s) => s.deadzone = v),
                settings.deadzone.toStringAsFixed(2)),
            _sliderTile('摇杆曲线（0 线性，1 中间更细腻）', settings.expo, 0, 1, 20, (v) => _set((s) => s.expo = v),
                settings.expo.toStringAsFixed(2)),
            SwitchListTile(
              title: const Text('左右轮对调'),
              value: settings.swapWheels,
              onChanged: (v) => _set((s) => s.swapWheels = v),
            ),
            SwitchListTile(
              title: const Text('反转前进方向'),
              value: settings.invertForward,
              onChanged: (v) => _set((s) => s.invertForward = v),
            ),
            const Divider(height: 32),
            const _AboutTile(),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile(String title, double value, double min, double max, int divisions,
      ValueChanged<double> onChanged, String readout) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text('$title：$readout'),
      Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
    ]);
  }
}

/// App name, version and licenses.
class _AboutTile extends StatelessWidget {
  const _AboutTile();

  static const _name = 'HelloBalls 遥控器';
  static const _stage = '预览版';
  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset('assets/branding/app_icon.png', width: 44, height: 44),
    );
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snap) {
        final info = snap.data;
        final version = info == null ? '' : '${info.version} (${info.buildNumber}) ';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: icon,
          title: const Text(_name),
          subtitle: Text('${version.isEmpty ? '' : '版本 $version· '}$_stage · 蓝牙协议 v$protocolVersion'),
          trailing: TextButton(
            child: const Text('开源许可'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: _name,
              applicationVersion: '$version$_stage',
              applicationIcon: Padding(padding: const EdgeInsets.all(8), child: icon),
            ),
          ),
        );
      },
    );
  }
}
