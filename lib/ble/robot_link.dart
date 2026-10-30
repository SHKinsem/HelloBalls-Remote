import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../binding/remote_model.dart';
import '../od/od_client.dart';
import '../od/od_dictionary.dart';
import '../od/od_protocol.dart';
import 'health.dart';
import 'protocol.dart';
import 'robot_transport.dart';

/// Owns the connection to one robot: sends the control frame at a fixed rate
/// (it doubles as heartbeat) and exposes the latest status.
class RobotLink extends ChangeNotifier {
  RobotLink(this.transport, this.model, {OdCache? odCache}) : odCache = odCache ?? MemoryOdCache();

  final RobotTransport transport;
  final RemoteModel model;
  final OdCache odCache;

  /// Object dictionary client, when the firmware has one (Info says "od=1").
  OdClient? od;
  StreamSubscription<List<int>>? _sdoSub;
  StreamSubscription<List<int>>? _tpdoSub;
  Future<OdDictionary>? _dictionaryLoad;

  /// Boot stage and faults: from the advertisement, then polled from 0x2001 while connected.
  RobotHealth? health;
  String? healthReason;
  Timer? _healthTimer;
  bool _healthBusy = false;

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
  bool _statusWasFresh = false;

  bool get connected => state == LinkState.connected;

  /// True when status frames keep arriving (robot alive and in range).
  bool get statusFresh =>
      lastStatusAt != null && clock.now().difference(lastStatusAt!) < const Duration(seconds: 1);

  Future<void> connect(FoundRobot robot) async {
    await disconnect();
    robotName = robot.name;
    health = robot.health;
    healthReason = null;
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
          lastStatusAt = clock.now();
          _statusWasFresh = true;
          notifyListeners();
        }
      }, onError: (Object e) => error = '状态订阅失败：$e');
      transport.readInfo().then((v) {
        info = v;
        if (v.split(';').contains('od=1')) _setupOd();
        notifyListeners();
      }).catchError((Object _) {});
      _startTicker();
    } else if (s == LinkState.disconnected) {
      _stop();
      if (was != LinkState.disconnected) error ??= '连接已断开';
    }
    notifyListeners();
  }

  void _setupOd() {
    if (od != null || !connected) return;
    final client = OdClient(transport.writeSdo);
    od = client;
    transport.requestMtu(preferredMtu).catchError((Object _) => 23);
    _sdoSub = transport.sdoStream().listen(client.handleSdo, onError: (Object e) => error = '字典订阅失败：$e');
    _tpdoSub = transport.tpdoStream().listen(client.handleTpdo, onError: (Object _) {});
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollHealth(client));
  }

  Future<void> _pollHealth(OdClient client) async {
    if (_healthBusy) return;
    _healthBusy = true;
    try {
      final stage = await client.readTyped(0x2001, 1, OdType.u8) as int;
      final faults = await client.readTyped(0x2001, 2, OdType.u32) as int;
      final h = RobotHealth(stage, faults);
      if (h != health || healthReason == null) {
        final reason = OdType.str.decode(await client.readBytes(0x2001, 3)) as String;
        if (od != client) return;
        health = h;
        healthReason = reason;
        notifyListeners();
      }
    } on OdException catch (e) {
      // firmware without diagnostics: stop asking
      if (e.code == 0x06020000 || e.code == 0x06090011) {
        _healthTimer?.cancel();
        _healthTimer = null;
      }
    } finally {
      _healthBusy = false;
    }
  }

  /// The robot's object dictionary, read once per connection (cached by checksum).
  Future<OdDictionary> loadDictionary() {
    final client = od;
    if (client == null) return Future.error(OdException('这台机器人的固件没有对象字典'));
    return _dictionaryLoad ??= client.loadDictionary(odCache).catchError((Object e) {
      _dictionaryLoad = null;
      throw e;
    });
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
    if (!connected) return;
    // Status frames carry their own notify; their absence has to be noticed here
    final fresh = statusFresh;
    if (fresh != _statusWasFresh) {
      _statusWasFresh = fresh;
      notifyListeners();
    }
    if (_writing) return; // skip a tick rather than queue stale frames
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
    _healthTimer?.cancel();
    _healthTimer = null;
    _sdoSub?.cancel();
    _sdoSub = null;
    _tpdoSub?.cancel();
    _tpdoSub = null;
    od?.close();
    od = null;
    _dictionaryLoad = null;
    _statusWasFresh = false;
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
    // not awaited: cancelling an async* stream waits for its generator, which may be parked
    unawaited(_stateSub?.cancel());
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
