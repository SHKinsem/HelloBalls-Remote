import 'dart:async';

import 'package:flutter/foundation.dart';

import '../binding/remote_model.dart';
import 'protocol.dart';
import 'robot_transport.dart';

/// Owns the connection to one robot: sends the control frame at a fixed rate
/// (it doubles as heartbeat) and exposes the latest status.
class RobotLink extends ChangeNotifier {
  RobotLink(this.transport, this.model);

  final RobotTransport transport;
  final RemoteModel model;

  LinkState state = LinkState.disconnected;
  StatusFrame? status;
  DateTime? lastStatusAt;
  String? robotName;
  String? info;
  String? error;
  int framesSent = 0;

  int _seq = 0;
  Timer? _ticker;
  StreamSubscription<LinkState>? _stateSub;
  StreamSubscription<List<int>>? _statusSub;
  bool _writing = false;

  bool get connected => state == LinkState.connected;

  /// True when status frames keep arriving (robot alive and in range).
  bool get statusFresh =>
      lastStatusAt != null && DateTime.now().difference(lastStatusAt!) < const Duration(seconds: 1);

  Future<void> connect(FoundRobot robot) async {
    await disconnect();
    robotName = robot.name;
    error = null;
    model.reset(); // never resume driving with stale stick values
    state = LinkState.connecting;
    notifyListeners();
    _stateSub = transport.connect(robot.id).listen(_onLinkState);
  }

  void _onLinkState(LinkState s) {
    final was = state;
    state = s;
    if (s == LinkState.connected && was != LinkState.connected) {
      _statusSub = transport.statusStream().listen((data) {
        final st = StatusFrame.decode(data);
        if (st != null) {
          status = st;
          lastStatusAt = DateTime.now();
          notifyListeners();
        }
      }, onError: (Object e) => error = '状态订阅失败：$e');
      transport.readInfo().then((v) {
        info = v;
        notifyListeners();
      }).catchError((Object _) {});
      _startTicker();
    } else if (s == LinkState.disconnected) {
      _stop();
      if (was != LinkState.disconnected) error ??= '连接已断开';
    }
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    final period = Duration(milliseconds: (1000 / model.settings.sendHz).round());
    _ticker = Timer.periodic(period, (_) => _sendControl());
  }

  /// Restart the send loop after the rate setting changed.
  void restartTicker() {
    if (connected) _startTicker();
  }

  Future<void> _sendControl() async {
    if (!connected || _writing) return; // skip a tick rather than queue stale frames
    _writing = true;
    try {
      _seq = (_seq + 1) & 0xFF;
      await transport.writeControl(model.buildFrame(_seq).encode());
      framesSent++;
    } catch (e) {
      error = '发送失败：$e';
      notifyListeners();
    } finally {
      _writing = false;
    }
  }

  Future<void> sendAction(int action) async {
    if (!connected) return;
    try {
      await transport.writeAction(ActionFrame(action).encode());
    } catch (e) {
      error = '指令发送失败：$e';
      notifyListeners();
    }
  }

  Future<void> emergencyStop() async {
    model.reset();
    await sendAction(actionEstop);
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _statusSub?.cancel();
    _statusSub = null;
  }

  /// Release control with an all-zero frame, then drop the link.
  /// The firmware also stops on its own when the link drops or frames stop.
  Future<void> disconnect() async {
    if (connected) {
      model.reset();
      try {
        await transport.writeControl(model.buildFrame((_seq + 1) & 0xFF).encode());
      } catch (_) {}
    }
    _stop();
    await _stateSub?.cancel();
    _stateSub = null;
    await transport.disconnect();
    if (state != LinkState.disconnected) {
      state = LinkState.disconnected;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stop();
    _stateSub?.cancel();
    super.dispose();
  }
}
