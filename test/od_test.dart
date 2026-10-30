import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloballs_remote/ble/demo_transport.dart';
import 'package:helloballs_remote/ble/robot_link.dart';
import 'package:helloballs_remote/ble/robot_transport.dart';
import 'package:helloballs_remote/binding/remote_model.dart';
import 'package:helloballs_remote/binding/remote_settings.dart';
import 'package:helloballs_remote/ble/protocol.dart';
import 'package:helloballs_remote/od/demo_od.dart';
import 'package:helloballs_remote/od/od_client.dart';
import 'package:helloballs_remote/od/od_dictionary.dart';
import 'package:helloballs_remote/od/od_protocol.dart';

List<int> _hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// An OdClient wired straight to a DemoOdServer.
(OdClient, DemoOdServer) _pair({bool inControl = true, int maxPayload = 244}) {
  late OdClient client;
  final server = DemoOdServer(remoteInControl: () => inControl);
  client = OdClient((frame) async {
    final rsp = server.handle(frame, maxPayload: maxPayload);
    Future<void>.delayed(Duration.zero, () => client.handleSdo(rsp));
  });
  return (client, server);
}

void main() {
  group('frames match the firmware vectors', () {
    final vectors = (jsonDecode(File('test/od_vectors.json').readAsStringSync())['sdo'] as List).cast<Map>();
    for (final v in vectors) {
      test(v['name'] as String, () {
        final req = _hex(v['req'] as String);
        final rsp = _hex(v['rsp'] as String);
        final r = SdoFrame.decode(req);
        if (r != null) expect(r.encode(), req);
        final a = SdoFrame.decode(rsp)!;
        expect(a.encode(), rsp);
        expect(a.seq, req[0]);
        if (a.cmd == sdoAbort) expect(abortMessage(a.abortCode), isNot(contains('拒绝了请求')));
      });
    }

    test('request builders', () {
      expect(SdoFrame.read(1, 0x2000, 2).encode(), _hex('014000200200'));
      expect(SdoFrame.write(2, 0x2001, 1, OdType.f32.encode(2.5)).encode(), _hex('02230120010400002040'));
      expect(OdType.i16.decode(_hex('2efb')), -1234);
      expect(pdoMapWord(0x2600, 6, 32), 0x26000620);
    });
  });

  group('client against the demo dictionary', () {
    test('loads the descriptor in segments and caches it', () async {
      final (od, server) = _pair(maxPayload: 40); // small MTU: many segments
      final cache = MemoryOdCache();
      final dict = await od.loadDictionary(cache);
      expect(dict.crc, server.descriptorCrc);
      expect(dict.entry(0x2600, 2)!.enums, isNotEmpty);
      expect(await cache.load(server.descriptorCrc), server.descriptor);
    });

    test('reads, writes and reports aborts', () async {
      final (od, _) = _pair();
      await od.loadDictionary(MemoryOdCache());
      expect(await od.read(0x1008, 0), 'HelloBalls-演示');
      expect(await od.write(0x2600, 5, 800), 800);
      expect(await od.read(0x2600, 5), 800);
      await expectLater(od.write(0x2600, 5, 99999),
          throwsA(isA<OdException>().having((e) => e.code, 'code', 0x06090030)));
      await expectLater(od.readTyped(0x7777, 0, OdType.u8),
          throwsA(isA<OdException>().having((e) => e.code, 'code', 0x06020000)));
    });

    test('debug mode needs the remote in control', () async {
      final (od, _) = _pair(inControl: false);
      await od.loadDictionary(MemoryOdCache());
      await expectLater(od.write(0x2600, 1, true),
          throwsA(isA<OdException>().having((e) => e.code, 'code', 0x08000022)));
    });

    test('TPDO frames decode by the mapping', () async {
      final (od, server) = _pair();
      await od.loadDictionary(MemoryOdCache());
      await od.write(0x2600, 1, true);
      await od.write(0x2600, 2, 3);
      await od.write(0x2600, 3, 300.0);
      await od.write(0x2600, 4, true);
      await od.enableTpdo(2, periodMs: 20);
      for (var i = 0; i < 50; i++) {
        server.tick(0.02);
      }
      final got = od.tpdoStream.first;
      for (final f in server.dueTpdos(100000)) {
        od.handleTpdo(f);
      }
      final v = await got;
      expect(v.pdo, 2);
      expect(v.values[odKey(0x2600, 6)], closeTo(300, 0.01));
      expect(v.values[odKey(0x2600, 7)], greaterThan(250));
      expect(v.values[odKey(0x2600, 4)], isTrue);
    });

    test('a request with no answer times out after retries', () async {
      var sent = 0;
      final od = OdClient((_) async => sent++, timeout: const Duration(milliseconds: 20), retries: 2);
      await expectLater(od.readTyped(0x1000, 0, OdType.u8), throwsA(isA<OdException>()));
      expect(sent, 3);
    });
  });

  test('motor debug through the demo robot: takeover, run, leave on release of control', () {
    fakeAsync((async) {
      final model = RemoteModel(RemoteSettings());
      final transport = DemoTransport();
      final link = RobotLink(transport, model);
      link.connect(const FoundRobot('demo', 'demo', -40));
      async.elapse(const Duration(seconds: 1));
      expect(link.od, isNotNull);

      OdDictionary? dict;
      link.loadDictionary().then((d) => dict = d);
      async.elapse(const Duration(seconds: 2));
      expect(dict, isNotNull);
      final od = link.od!;

      Object? error;
      od.write(0x2600, 1, true).catchError((Object e) => error = e);
      async.elapse(const Duration(milliseconds: 100));
      expect(error, isA<OdException>()); // no takeover yet

      model.setTakeover(true);
      model.setState(HostState.idle);
      async.elapse(const Duration(milliseconds: 200));
      od.write(0x2600, 1, true);
      od.write(0x2600, 2, 4);
      od.write(0x2600, 3, 400.0);
      od.write(0x2600, 4, true);
      final frames = <TpdoValues>[];
      od.tpdoStream.listen(frames.add);
      od.enableTpdo(2, periodMs: 50);
      async.elapse(const Duration(seconds: 2));
      expect(frames.length, greaterThan(20));
      expect(frames.last.values[odKey(0x2600, 6)], closeTo(400, 0.01));
      expect(transport.od.motorSpeed[3], greaterThan(350));

      // dropping takeover leaves debug mode and stops the motor
      model.reset();
      async.elapse(const Duration(seconds: 1));
      expect(transport.od.debugMode, isFalse);
      expect(transport.od.motorSpeed[3].abs(), lessThan(50));
      link.disconnect();
      async.flushMicrotasks();
    });
  });
}
