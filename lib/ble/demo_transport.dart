import 'dart:async';

import 'package:clock/clock.dart';

import '../od/demo_od.dart';
import 'protocol.dart';
import 'robot_transport.dart';

/// A simulated robot for trying the app without hardware. It follows the same
/// rules as the firmware: commands count only with takeover, wheels follow the
/// command with some lag, and the emergency stop latches.
class DemoTransport implements RobotTransport {
  final _status = StreamController<List<int>>.broadcast();
  Timer? _timer;
  ControlFrame _last = const ControlFrame();
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _estop = false;
  double _w1 = 0, _w2 = 0;
  final _start = clock.now();
  final _sdo = StreamController<List<int>>.broadcast();
  final _tpdo = StreamController<List<int>>.broadcast();
  Timer? _odTimer;
  late final DemoOdServer od = DemoOdServer(remoteInControl: _remoteInControl);

  bool _remoteInControl() =>
      clock.now().difference(_lastAt) < const Duration(milliseconds: 300) &&
      (_last.flags & flagTakeover) != 0 &&
      _last.state == HostState.idle.value &&
      !_estop;

  @override
  Future<String?> ensureReady() async => null;

  @override
  Stream<FoundRobot> scan() => Stream.value(FoundRobot('demo', 'HelloBalls-演示', -40, od.health));

  @override
  Stream<LinkState> connect(String id) async* {
    yield LinkState.connecting;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _odTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      od.tick(0.02);
      final now = clock.now().difference(_start).inMilliseconds;
      for (final f in od.dueTpdos(now)) {
        _tpdo.add(f);
      }
    });
    yield LinkState.connected;
  }

  void _tick() {
    final fresh = clock.now().difference(_lastAt) < const Duration(milliseconds: 300);
    final takeover = fresh && (_last.flags & flagTakeover) != 0 && !_estop;
    final driving = takeover && const [1, 2, 4].contains(_last.state);
    final t1 = driving ? _last.wheel1Rpm.toDouble() : 0.0;
    final t2 = driving ? _last.wheel2Rpm.toDouble() : 0.0;
    _w1 += (t1 - _w1) * 0.4;
    _w2 += (t2 - _w2) * 0.4;
    final st = StatusFrame(
      mcuState: _estop ? 5 : (takeover && _last.state == 1 ? 1 : 0),
      hostState: takeover ? _last.state : 0,
      activeSrc: takeover ? ActiveSource.ble.index : ActiveSource.none.index,
      flags: (_estop ? statusEstop : 0) | (takeover ? statusTakeover : 0),
      lastSeq: _last.seq,
      wheel1Rpm: _w1.round(),
      wheel2Rpm: _w2.round(),
      uptimeMs: clock.now().difference(_start).inMilliseconds,
    );
    _status.add(st.encode());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _odTimer?.cancel();
    _odTimer = null;
    od.debugMode = false;
    od.debugRun = false;
    od.tpdoEnabled.fillRange(0, 4, false);
  }

  @override
  Future<void> writeControl(List<int> frame) async {
    final f = ControlFrame.decode(frame);
    if (f == null) return;
    _last = f;
    _lastAt = clock.now();
  }

  @override
  Future<void> writeAction(List<int> frame) async {
    final a = ActionFrame.decode(frame);
    if (a?.action == actionEstop) _estop = true;
    if (a?.action == actionClearEstop) _estop = false;
  }

  @override
  Stream<List<int>> statusStream() => _status.stream;

  @override
  Future<String> readInfo() async => 'proto=$protocolVersion;od=1;fw=demo';

  @override
  Future<int> requestMtu(int mtu) async => mtu;

  @override
  Future<void> writeSdo(List<int> frame) async {
    final rsp = od.handle(frame);
    // Answer a moment later, as over the air
    Timer(const Duration(milliseconds: 5), () => _sdo.add(rsp));
  }

  @override
  Stream<List<int>> sdoStream() => _sdo.stream;

  @override
  Stream<List<int>> tpdoStream() => _tpdo.stream;
}
