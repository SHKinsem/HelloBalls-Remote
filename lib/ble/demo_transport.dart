import 'dart:async';

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
  final _start = DateTime.now();

  @override
  Future<String?> ensureReady() async => null;

  @override
  Stream<FoundRobot> scan() => Stream.value(const FoundRobot('demo', 'HelloBalls-演示', -40));

  @override
  Stream<LinkState> connect(String id) async* {
    yield LinkState.connecting;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    yield LinkState.connected;
  }

  void _tick() {
    final fresh = DateTime.now().difference(_lastAt) < const Duration(milliseconds: 300);
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
      uptimeMs: DateTime.now().difference(_start).inMilliseconds,
    );
    _status.add(st.encode());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> writeControl(List<int> frame) async {
    final f = ControlFrame.decode(frame);
    if (f == null) return;
    _last = f;
    _lastAt = DateTime.now();
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
  Future<String> readInfo() async => 'proto=$protocolVersion;fw=demo';
}
