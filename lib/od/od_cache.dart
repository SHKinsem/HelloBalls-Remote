import 'package:shared_preferences/shared_preferences.dart';

import 'od_client.dart';

/// Keeps the last few dictionary descriptors on the phone, keyed by checksum,
/// so reconnecting to the same firmware does not download them again.
class PrefsOdCache implements OdCache {
  static const _prefix = 'od_desc_';
  static const _keep = 3;

  @override
  Future<String?> load(int crc) async => (await SharedPreferences.getInstance()).getString('$_prefix$crc');

  @override
  Future<void> save(int crc, String json) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    if (old.length >= _keep) {
      for (final k in old.take(old.length - _keep + 1)) {
        await prefs.remove(k);
      }
    }
    await prefs.setString('$_prefix$crc', json);
  }
}
