// Object dictionary over BLE: SDO and TPDO frames, mirrors the firmware's
// obj_dict component (HelloBalls-2.0: components/obj_dict). Both sides are
// checked against test/od_vectors.json, copied from
// components/obj_dict/test/vectors.json.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

final Uuid sdoUuid = Uuid.parse('b5f90006-7a4c-4e57-9c1d-48a7a3b4c0de');
final Uuid tpdoUuid = Uuid.parse('b5f90008-7a4c-4e57-9c1d-48a7a3b4c0de');

/// MTU the app asks for; the firmware prefers the same.
const int preferredMtu = 247;

/// Data types (CANopen codes).
enum OdType {
  boolean(0x01, 1),
  i8(0x02, 1),
  i16(0x03, 2),
  i32(0x04, 4),
  u8(0x05, 1),
  u16(0x06, 2),
  u32(0x07, 4),
  f32(0x08, 4),
  str(0x09, 0),
  domain(0x0F, 0);

  const OdType(this.code, this.size);
  final int code;
  final int size; // bytes, 0 for variable length

  bool get isNumeric => size > 0;
  bool get isInteger => size > 0 && this != f32 && this != boolean;

  static OdType? fromCode(int c) {
    for (final t in values) {
      if (t.code == c) return t;
    }
    return null;
  }

  /// Integer range of the type itself.
  (num, num) get limits => switch (this) {
        boolean => (0, 1),
        i8 => (-128, 127),
        u8 => (0, 255),
        i16 => (-32768, 32767),
        u16 => (0, 65535),
        i32 => (-2147483648, 2147483647),
        u32 => (0, 4294967295),
        _ => (double.negativeInfinity, double.infinity),
      };

  Uint8List encode(Object value) {
    final b = ByteData(size == 0 ? 0 : size);
    switch (this) {
      case boolean:
        b.setUint8(0, value == true || (value is num && value != 0) ? 1 : 0);
      case i8:
        b.setInt8(0, (value as num).round());
      case u8:
        b.setUint8(0, (value as num).round());
      case i16:
        b.setInt16(0, (value as num).round(), Endian.little);
      case u16:
        b.setUint16(0, (value as num).round(), Endian.little);
      case i32:
        b.setInt32(0, (value as num).round(), Endian.little);
      case u32:
        b.setUint32(0, (value as num).round(), Endian.little);
      case f32:
        b.setFloat32(0, (value as num).toDouble(), Endian.little);
      case str:
        return Uint8List.fromList(utf8.encode(value as String));
      case domain:
        return Uint8List.fromList(value as List<int>);
    }
    return b.buffer.asUint8List();
  }

  /// Decodes a value: bool, int, double, String (str) or Uint8List (domain). Null if the length is wrong.
  Object? decode(List<int> data, [int offset = 0]) {
    if (size != 0 && data.length - offset < size) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data), offset);
    return switch (this) {
      boolean => b.getUint8(0) != 0,
      i8 => b.getInt8(0),
      u8 => b.getUint8(0),
      i16 => b.getInt16(0, Endian.little),
      u16 => b.getUint16(0, Endian.little),
      i32 => b.getInt32(0, Endian.little),
      u32 => b.getUint32(0, Endian.little),
      f32 => b.getFloat32(0, Endian.little),
      str => _utf8(data.sublist(offset)),
      domain => Uint8List.fromList(data.sublist(offset)),
    };
  }
}

String _utf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// Access rights and flags (obj_dict.h).
const int odRead = 0x01;
const int odWrite = 0x02;
const int flagPdo = 0x01;
const int flagStore = 0x02;
const int flagTakeover = 0x04;
const int flagIdle = 0x08;
const int flagConfirm = 0x10;
const int flagRange = 0x80;

/// SDO commands.
const int sdoRead = 0x40;
const int sdoReadRsp = 0x43;
const int sdoSegRead = 0x41;
const int sdoSegReadRsp = 0x42;
const int sdoWrite = 0x23;
const int sdoWriteRsp = 0x60;
const int sdoAbort = 0x80;
const int sdoHeader = 6;

/// Signatures for 0x1010 (save) and 0x1011 (restore defaults), as in CANopen.
const int saveSignature = 0x65766173;
const int loadSignature = 0x64616F6C;

/// SDO abort codes and what to tell the user.
const Map<int, String> abortMessages = {
  0x05030000: '机器人不认识这个指令',
  0x06010001: '这个条目只能写不能读',
  0x06010002: '这个条目是只读的',
  0x06020000: '机器人上没有这个对象（固件版本不同？）',
  0x06040041: '这个条目不能放进 PDO',
  0x06040042: 'PDO 超出长度',
  0x06070010: '数据长度不对',
  0x06090011: '机器人上没有这个子索引（固件版本不同？）',
  0x06090030: '数值超出允许范围',
  0x08000000: '机器人内部错误',
  0x08000020: '保存到闪存失败',
  0x08000022: '机器人当前状态不允许：需要接管、未急停，且停转/待机',
};

String abortMessage(int code) =>
    abortMessages[code] ?? '机器人拒绝了请求（0x${code.toRadixString(16).padLeft(8, '0')}）';

/// One SDO frame: seq | cmd | index u16 | sub | len | data.
class SdoFrame {
  const SdoFrame(this.seq, this.cmd, this.index, this.sub, [this.data = const []]);

  final int seq;
  final int cmd;
  final int index;
  final int sub;
  final List<int> data;

  Uint8List encode() {
    final b = BytesBuilder();
    b.add([seq & 0xFF, cmd & 0xFF, index & 0xFF, (index >> 8) & 0xFF, sub & 0xFF, data.length & 0xFF]);
    b.add(data);
    return b.toBytes();
  }

  static SdoFrame? decode(List<int> raw) {
    if (raw.length < sdoHeader || raw.length != sdoHeader + raw[5]) return null;
    return SdoFrame(raw[0], raw[1], raw[2] | (raw[3] << 8), raw[4], raw.sublist(sdoHeader));
  }

  int get abortCode => data.length >= 4 ? ByteData.sublistView(Uint8List.fromList(data)).getUint32(0, Endian.little) : 0;

  static SdoFrame read(int seq, int index, int sub) => SdoFrame(seq, sdoRead, index, sub);
  static SdoFrame write(int seq, int index, int sub, List<int> value) => SdoFrame(seq, sdoWrite, index, sub, value);
  static SdoFrame segRead(int seq, int index, int sub, int offset) =>
      SdoFrame(seq, sdoSegRead, index, sub, OdType.u32.encode(offset));
}

/// A TPDO frame: pdo | seq | t_ms u16 | mapped values.
class TpdoFrame {
  const TpdoFrame(this.pdo, this.seq, this.timeMs, this.payload);

  final int pdo; // 1-4
  final int seq;
  final int timeMs;
  final List<int> payload;

  static TpdoFrame? decode(List<int> raw) {
    if (raw.length < 4) return null;
    return TpdoFrame(raw[0], raw[1], raw[2] | (raw[3] << 8), raw.sublist(4));
  }
}

/// index << 16 | sub << 8 | bits, as in CANopen.
int pdoMapWord(int index, int sub, int bits) => (index << 16) | (sub << 8) | bits;
