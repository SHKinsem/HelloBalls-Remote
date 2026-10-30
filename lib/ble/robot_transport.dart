import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'protocol.dart';

/// A robot found while scanning.
class FoundRobot {
  const FoundRobot(this.id, this.name, this.rssi);
  final String id;
  final String name;
  final int rssi;
}

enum LinkState { disconnected, connecting, connected }

/// The Bluetooth operations RobotLink needs. Lets tests swap in a fake robot.
abstract class RobotTransport {
  Future<String?> ensureReady(); // null when ready, otherwise a message for the user
  Stream<FoundRobot> scan();
  Stream<LinkState> connect(String id);
  Future<void> disconnect();
  Future<void> writeControl(List<int> frame);
  Future<void> writeAction(List<int> frame);
  Stream<List<int>> statusStream();
  Future<String> readInfo();
}

class ReactiveBleTransport implements RobotTransport {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _conn;
  String? _deviceId;

  QualifiedCharacteristic _chr(Uuid c) =>
      QualifiedCharacteristic(serviceId: serviceUuid, characteristicId: c, deviceId: _deviceId!);

  @override
  Future<String?> ensureReady() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse, // only needed on Android 11 and older
      ].request();
      final scan = results[Permission.bluetoothScan];
      final loc = results[Permission.locationWhenInUse];
      if (scan != PermissionStatus.granted && loc != PermissionStatus.granted) {
        return '需要“附近的设备”（蓝牙）权限才能扫描机器人';
      }
    }
    final status = await _ble.statusStream.firstWhere((s) => s != BleStatus.unknown);
    switch (status) {
      case BleStatus.ready:
        return null;
      case BleStatus.poweredOff:
        return '请先打开手机蓝牙';
      case BleStatus.unauthorized:
        return '没有蓝牙权限，请在系统设置里允许';
      case BleStatus.locationServicesDisabled:
        return '请打开定位服务（旧版 Android 扫描蓝牙需要）';
      case BleStatus.unsupported:
        return '这台设备不支持低功耗蓝牙';
      default:
        return '蓝牙状态：$status';
    }
  }

  @override
  Stream<FoundRobot> scan() => _ble
      .scanForDevices(withServices: [serviceUuid], scanMode: ScanMode.lowLatency)
      .map((d) => FoundRobot(d.id, d.name.isEmpty ? '未命名设备' : d.name, d.rssi));

  @override
  Stream<LinkState> connect(String id) {
    final controller = StreamController<LinkState>();
    _deviceId = id;
    _conn?.cancel();
    _conn = _ble
        .connectToDevice(
          id: id,
          servicesWithCharacteristicsToDiscover: {
            serviceUuid: [controlUuid, actionUuid, statusUuid, infoUuid],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen((u) {
      switch (u.connectionState) {
        case DeviceConnectionState.connecting:
          controller.add(LinkState.connecting);
        case DeviceConnectionState.connected:
          _ble.requestConnectionPriority(deviceId: id, priority: ConnectionPriority.highPerformance).ignore();
          controller.add(LinkState.connected);
        case DeviceConnectionState.disconnecting:
        case DeviceConnectionState.disconnected:
          controller.add(LinkState.disconnected);
      }
    }, onError: (Object e) {
      controller.add(LinkState.disconnected);
    });
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    await _conn?.cancel();
    _conn = null;
  }

  @override
  Future<void> writeControl(List<int> frame) =>
      _ble.writeCharacteristicWithoutResponse(_chr(controlUuid), value: frame);

  @override
  Future<void> writeAction(List<int> frame) =>
      _ble.writeCharacteristicWithResponse(_chr(actionUuid), value: frame);

  @override
  Stream<List<int>> statusStream() => _ble.subscribeToCharacteristic(_chr(statusUuid));

  @override
  Future<String> readInfo() async => String.fromCharCodes(await _ble.readCharacteristic(_chr(infoUuid)));
}
