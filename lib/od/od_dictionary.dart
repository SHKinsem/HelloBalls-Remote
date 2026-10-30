import 'dart:convert';

import 'od_protocol.dart';

/// One index:subindex entry, as described by the robot (0x1021).
class OdEntry {
  OdEntry({
    required this.index,
    required this.sub,
    required this.name,
    required this.type,
    required this.access,
    required this.flags,
    this.unit,
    this.min,
    this.max,
    this.enums,
  });

  final int index;
  final int sub;
  final String name;
  final OdType type;
  final int access;
  final int flags;
  final String? unit;
  final num? min;
  final num? max;
  final List<String>? enums;

  bool get readable => access & odRead != 0;
  bool get writable => access & odWrite != 0;
  bool get mappable => flags & flagPdo != 0;
  bool get stored => flags & flagStore != 0;
  bool get needsConfirm => flags & flagConfirm != 0;
  bool get needsIdle => flags & flagIdle != 0;
  bool get needsTakeover => flags & flagTakeover != 0;

  String get key => odKey(index, sub);
  String get address => '0x${index.toRadixString(16).toUpperCase().padLeft(4, '0')}.$sub';

  /// The value as the user should read it: enum label, unit, rounded floats.
  String format(Object? v) {
    if (v == null) return '-';
    if (v is bool) return v ? '是' : '否';
    if (enums != null && v is int && v >= 0 && v < enums!.length) return enums![v];
    var text = v is double ? _trim(v) : '$v';
    if (unit != null) text = '$text $unit';
    return text;
  }

  /// Parses user input; returns an error message instead of a value when it is not acceptable.
  ({Object? value, String? error}) parse(String input) {
    final s = input.trim();
    if (type == OdType.str) return (value: s, error: null);
    if (type == OdType.boolean) {
      if (['1', 'true', '是', 'on'].contains(s.toLowerCase())) return (value: true, error: null);
      if (['0', 'false', '否', 'off'].contains(s.toLowerCase())) return (value: false, error: null);
      return (value: null, error: '请输入 1 或 0');
    }
    final n = type.isInteger ? int.tryParse(s) : double.tryParse(s);
    if (n == null) return (value: null, error: type.isInteger ? '请输入整数' : '请输入数字');
    return check(n);
  }

  ({Object? value, String? error}) check(num n) {
    final (lo, hi) = range;
    if (n < lo || n > hi) return (value: null, error: '范围 ${_trim(lo)} 到 ${_trim(hi)}');
    return (value: n, error: null);
  }

  /// Allowed range: the robot's limits when it gave some, else the type's.
  (num, num) get range => (min != null && max != null) ? (min!, max!) : type.limits;

  static String _trim(num v) {
    if (v is int || v == v.roundToDouble() && v.abs() < 1e9) return v.round().toString();
    final s = v.toStringAsPrecision(6);
    return s.contains('.') && !s.contains('e') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }
}

class OdObject {
  OdObject(this.index, this.name, this.entries);

  final int index;
  final String name;
  final List<OdEntry> entries;

  String get address => '0x${index.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

String odKey(int index, int sub) => '$index.$sub';

/// The whole dictionary, parsed from the robot's JSON descriptor.
class OdDictionary {
  OdDictionary(this.objects, this.crc) : _byKey = {for (final o in objects) for (final e in o.entries) e.key: e};

  final List<OdObject> objects;
  final int crc;
  final Map<String, OdEntry> _byKey;

  OdEntry? entry(int index, int sub) => _byKey[odKey(index, sub)];
  OdObject? object(int index) {
    for (final o in objects) {
      if (o.index == index) return o;
    }
    return null;
  }

  int get entryCount => _byKey.length;

  /// Format (firmware obj_dict.h, od_describe):
  /// {"v":1,"o":[{"i":8705,"n":"...","e":[{"s":1,"n":"...","t":3,"a":1,"f":1,"u":"rpm","lo":-1,"hi":1,"en":["a"]}]}]}
  factory OdDictionary.parse(String json, int crc) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final objects = <OdObject>[];
    for (final o in root['o'] as List) {
      final index = o['i'] as int;
      final entries = <OdEntry>[];
      for (final e in o['e'] as List) {
        final type = OdType.fromCode(e['t'] as int);
        if (type == null) continue; // a type this app does not know: leave it out
        final flags = e['f'] as int;
        entries.add(OdEntry(
          index: index,
          sub: e['s'] as int,
          name: e['n'] as String,
          type: type,
          access: e['a'] as int,
          flags: flags,
          unit: e['u'] as String?,
          min: flags & flagRange != 0 ? e['lo'] as num? : null,
          max: flags & flagRange != 0 ? e['hi'] as num? : null,
          enums: (e['en'] as List?)?.cast<String>(),
        ));
      }
      objects.add(OdObject(index, o['n'] as String, entries));
    }
    return OdDictionary(objects, crc);
  }
}
