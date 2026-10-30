# HelloBalls 遥控器

用 Flutter 写的 HelloBalls 网球机器人蓝牙遥控器，通过 BLE 直连下位机 ESP32-S3（[HelloBalls-2.0](https://github.com/SHKinsem/HelloBalls-2.0) 的 `ble_remote` 组件）。

## 功能

- 扫描附近的机器人（按服务 UUID 过滤，广播名 `HelloBalls-XXXX`）
- 控件模块：摇杆（差速驾驶）、按键（模式切换、急停、长按确认）、滑条（俯仰角、摩擦轮，可松手回零）、开关（接管控制）、状态显示
- 布局写在 [`assets/layouts/default.json`](assets/layouts/default.json)，位置和大小按屏幕比例描述，改 JSON 就能调整界面
- 演示模式：不连机器人也能试用界面（扫描页右上角）
- 设置页：最大轮速、发送频率、摇杆死区和曲线、左右轮对调、反转前进方向

## 使用流程

1. 机器人上电，打开 App，点扫描到的 `HelloBalls-XXXX`。
2. 打开“接管控制”。不接管时机器人照常听上位机（串口）的，遥控器的指令会被忽略。
3. 默认是“驾驶”模式，用摇杆开车；“吸球 / 收球 / 发射”会触发固件里对应的动作。
4. 急停会锁住，必须长按“解除急停”才恢复。

断开连接、App 切到后台、停止发送超过 300 ms，固件都会让机器人停下并把控制权交还上位机。

## 构建

需要 Flutter 3.41 以上。

```bash
flutter pub get
flutter test          # 协议、混控、连接逻辑、界面测试
flutter build apk     # Android 安装包：build/app/outputs/flutter-apk/app-release.apk
flutter run           # 连手机直接运行
```

iOS 需要在 Mac 上用 Xcode 签名后安装。

## 代码结构

```
lib/
  ble/        protocol.dart（帧编解码）  robot_transport.dart（蓝牙）  robot_link.dart（连接和定时发送）  demo_transport.dart（模拟机器人）
  binding/    remote_model.dart（控件值 → 指令帧）  drive_mixer.dart（摇杆 → 左右轮）  remote_settings.dart
  controls/   joystick.dart  simple_controls.dart（按键、滑条、开关、状态）
  layout/     control_spec.dart（JSON 布局）
  pages/      scan_page.dart  remote_page.dart  settings_page.dart
```

## 协议

服务 `b5f90001-7a4c-4e57-9c1d-48a7a3b4c0de`，帧都是定长、小端序、首字节为协议版本（1）。

| 特征值 | UUID 尾号 | 属性 | 内容 |
| --- | --- | --- | --- |
| Control | `0002` | Write Without Response，默认 25 Hz | `ver, seq, state, flags, wheel1_rpm i16, wheel2_rpm i16, tilt_angle i16, shoot_speed i16`，12 B；`flags` bit0 = 接管控制 |
| Action | `0003` | Write | `ver, action, param i16`，4 B；`1` 急停，`2` 解除急停 |
| Status | `0004` | Read / Notify，10 Hz | `ver, mcu_state, host_state, active_src, flags, last_seq, wheel1_rpm i16, wheel2_rpm i16, uptime_ms u32`，14 B |
| Info | `0005` | Read | `proto=1;fw=<固件版本>` |

`test/vectors.json` 和固件仓库 `components/ble_remote/test/vectors.json` 是同一份测试向量，两边都用它来校验编解码。
