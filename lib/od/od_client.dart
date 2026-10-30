import 'dart:async';
import 'dart:typed_data';

import 'od_dictionary.dart';
import 'od_protocol.dart';

/// The robot refused a request (SDO abort) or did not answer.
class OdException implements Exception {
  OdException(this.message, [this.code]);
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// Where the dictionary descriptor is cached between connections, keyed by its checksum.
abstract class OdCache {
  Future<String?> load(int crc);
  Future<void> save(int crc, String json);
}

class MemoryOdCache implements OdCache {
  final _map = <int, String>{};
  @override
  Future<String?> load(int crc) async => _map[crc];
  @override
  Future<void> save(int crc, String json) async => _map[crc] = json;
}

/// Values carried by one TPDO frame, keyed by odKey(index, sub).
class TpdoValues {
  TpdoValues(this.pdo, this.timeMs, this.values);
  final int pdo;
  final int timeMs;
  final Map<String, Object?> values;
}

class _Mapped {
  _Mapped(this.key, this.type);
  final String key;
  final OdType type;
}

/// SDO client and TPDO decoder. One request is in flight at a time; a request
/// that gets no answer is sent again before giving up.
class OdClient {
  OdClient(this._send, {this.timeout = const Duration(milliseconds: 800), this.retries = 2});

  final Future<void> Function(List<int> frame) _send;
  final Duration timeout;
  final int retries;

  OdDictionary? dictionary;
  int _seq = 0;
  Completer<SdoFrame>? _pending;
  int _pendingSeq = -1;
  Future<void> _queue = Future.value();
  bool _closed = false;

  final _tpdoMaps = <int, List<_Mapped>>{};
  final _tpdo = StreamController<TpdoValues>.broadcast();

  /// Decoded TPDO frames of the PDOs enabled through [enableTpdo].
  Stream<TpdoValues> get tpdoStream => _tpdo.stream;

  /// Feed every SDO notification here.
  void handleSdo(List<int> raw) {
    final f = SdoFrame.decode(raw);
    if (f == null || f.seq != _pendingSeq) return; // late answer to a request already given up on
    final p = _pending;
    _pending = null;
    _pendingSeq = -1;
    if (p != null && !p.isCompleted) p.complete(f);
  }

  /// Feed every TPDO notification here.
  void handleTpdo(List<int> raw) {
    final f = TpdoFrame.decode(raw);
    if (f == null) return;
    final map = _tpdoMaps[f.pdo];
    if (map == null) return;
    final values = <String, Object?>{};
    var pos = 0;
    for (final m in map) {
      if (pos + m.type.size > f.payload.length) return;
      values[m.key] = m.type.decode(f.payload, pos);
      pos += m.type.size;
    }
    _tpdo.add(TpdoValues(f.pdo, f.timeMs, values));
  }

  void close() {
    _closed = true;
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.completeError(OdException('连接已断开'));
    _tpdo.close();
  }

  Future<SdoFrame> _request(SdoFrame Function(int seq) build) {
    final result = Completer<SdoFrame>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _exchange(build));
      } catch (e) {
        result.completeError(e);
      }
    });
    return result.future;
  }

  Future<SdoFrame> _exchange(SdoFrame Function(int seq) build) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (_closed) throw OdException('连接已断开');
      _seq = (_seq + 1) & 0xFF;
      final frame = build(_seq);
      final c = Completer<SdoFrame>();
      _pending = c;
      _pendingSeq = _seq;
      try {
        await _send(frame.encode());
      } catch (e) {
        _pending = null;
        _pendingSeq = -1;
        throw OdException('发送失败：$e');
      }
      try {
        final rsp = await c.future.timeout(timeout);
        if (rsp.cmd == sdoAbort) throw OdException(abortMessage(rsp.abortCode), rsp.abortCode);
        return rsp;
      } on TimeoutException {
        _pending = null;
        _pendingSeq = -1;
      }
    }
    throw OdException('机器人没有回应');
  }

  OdEntry _entryOf(int index, int sub) {
    final e = dictionary?.entry(index, sub);
    if (e == null) throw OdException('字典里没有 0x${index.toRadixString(16)}.$sub');
    return e;
  }

  /// Reads a fixed-size value of a known type.
  Future<Object?> readTyped(int index, int sub, OdType type) async {
    if (type.size == 0) return type.decode(await readBytes(index, sub));
    final rsp = await _request((s) => SdoFrame.read(s, index, sub));
    final v = type.decode(rsp.data);
    if (v == null) throw OdException('回应长度不对');
    return v;
  }

  Future<Object?> read(int index, int sub) {
    final e = _entryOf(index, sub);
    return readTyped(index, sub, e.type);
  }

  /// Reads a string or data block of any length, in segments.
  Future<Uint8List> readBytes(int index, int sub) async {
    final out = BytesBuilder();
    var total = -1;
    while (total < 0 || out.length < total) {
      final offset = out.length;
      final rsp = await _request((s) => SdoFrame.segRead(s, index, sub, offset));
      if (rsp.cmd != sdoSegReadRsp || rsp.data.length < 4) throw OdException('回应格式不对');
      total = OdType.u32.decode(rsp.data) as int;
      final chunk = rsp.data.sublist(4);
      if (chunk.isEmpty && out.length < total) throw OdException('数据不完整');
      out.add(chunk);
    }
    return out.toBytes();
  }

  /// Writes a value of a known type; returns the value now in effect (null for write-only entries).
  Future<Object?> writeTyped(int index, int sub, OdType type, Object value) async {
    final rsp = await _request((s) => SdoFrame.write(s, index, sub, type.encode(value)));
    return rsp.data.isEmpty ? null : type.decode(rsp.data);
  }

  Future<Object?> write(int index, int sub, Object value) {
    final e = _entryOf(index, sub);
    return writeTyped(index, sub, e.type, value);
  }

  /// Reads the descriptor (0x1021), using the cached copy when its checksum (0x1022) still matches.
  Future<OdDictionary> loadDictionary(OdCache cache) async {
    final crc = await readTyped(0x1022, 0, OdType.u32) as int;
    var json = await cache.load(crc);
    if (json == null) {
      json = OdType.str.decode(await readBytes(0x1021, 0)) as String;
      await cache.save(crc, json);
    }
    return dictionary = OdDictionary.parse(json, crc);
  }

  /// Reads TPDO [pdo]'s mapping so its frames can be decoded, sets its period and switches it on.
  Future<void> enableTpdo(int pdo, {int? periodMs}) async {
    final n = pdo - 1;
    final count = await readTyped(0x1A00 + n, 0, OdType.u8) as int;
    final map = <_Mapped>[];
    for (var k = 1; k <= count; k++) {
      final word = await readTyped(0x1A00 + n, k, OdType.u32) as int;
      final e = _entryOf(word >> 16, (word >> 8) & 0xFF);
      map.add(_Mapped(e.key, e.type));
    }
    _tpdoMaps[pdo] = map;
    if (periodMs != null) await writeTyped(0x1800 + n, 1, OdType.u16, periodMs);
    await writeTyped(0x1800 + n, 2, OdType.boolean, true);
  }

  Future<void> disableTpdo(int pdo) async {
    await writeTyped(0x1800 + pdo - 1, 2, OdType.boolean, false);
    _tpdoMaps.remove(pdo);
  }

  /// Saves every parameter marked "store" to the robot's flash.
  Future<void> saveParameters() => writeTyped(0x1010, 1, OdType.u32, saveSignature);

  /// Restores the default parameters in the robot's RAM (save afterwards to keep them).
  Future<void> restoreDefaults() => writeTyped(0x1011, 1, OdType.u32, loadSignature);
}
