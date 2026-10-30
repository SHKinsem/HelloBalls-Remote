import 'package:flutter/material.dart';

import '../ble/robot_link.dart';
import '../od/od_client.dart';
import '../od/od_dictionary.dart';

/// Every object the robot exposes, read live, with editing for the writable ones.
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key, required this.link});

  final RobotLink link;

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  OdDictionary? _dict;
  String? _error;
  final _values = <String, Object?>{};
  final _errors = <String, String>{};
  final _loading = <int>{};

  OdClient? get _od => widget.link.od;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await widget.link.loadDictionary();
      if (mounted) setState(() => _dict = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _readObject(OdObject o) async {
    final od = _od;
    if (od == null) return;
    setState(() => _loading.add(o.index));
    for (final e in o.entries.where((e) => e.readable)) {
      try {
        _values[e.key] = await od.read(e.index, e.sub);
        _errors.remove(e.key);
      } catch (err) {
        _errors[e.key] = '$err';
      }
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) setState(() => _loading.remove(o.index));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _edit(OdEntry e) async {
    final value = await askValue(context, e, _values[e.key]);
    if (value == null || !mounted) return;
    if (e.needsConfirm && !await _confirm('确认修改', '把“${e.name}”改成 ${e.format(value)}？')) return;
    try {
      final now = await _od!.write(e.index, e.sub, value);
      setState(() {
        if (e.readable) _values[e.key] = now;
        _errors.remove(e.key);
      });
      _snack(e.stored ? '已生效。要断电后保留，请点右上角“保存到机器人”' : '已生效');
    } catch (err) {
      _snack('修改失败：$err');
    }
  }

  Future<void> _save() async {
    if (!await _confirm('保存参数', '把当前所有可保存参数写入机器人闪存？需要电机停转、机器人待机。')) return;
    try {
      await _od!.saveParameters();
      _snack('已保存，重启后仍然有效');
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  Future<void> _restore() async {
    if (!await _confirm('恢复默认参数', '把所有参数恢复成固件默认值？已保存的值要再点“保存到机器人”才会被覆盖。')) return;
    try {
      await _od!.restoreDefaults();
      _values.clear();
      setState(() {});
      _snack('已恢复默认值（尚未保存）');
    } catch (e) {
      _snack('恢复失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dict = _dict;
    return Scaffold(
      appBar: AppBar(
        title: const Text('对象字典 / 参数'),
        actions: [
          if (dict != null) ...[
            TextButton.icon(onPressed: _restore, icon: const Icon(Icons.restore), label: const Text('恢复默认')),
            TextButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('保存到机器人')),
          ],
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('读取字典失败：$_error'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ]),
            )
          : dict == null
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在从机器人读取字典…（第一次连接需要几秒）'),
                  ]),
                )
              : ListView(children: [
                  for (final o in dict.objects)
                    ExpansionTile(
                      key: PageStorageKey(o.index),
                      title: Text(o.name),
                      subtitle: Text('${o.address} · ${o.entries.length} 项'),
                      trailing: _loading.contains(o.index)
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: () => _readObject(o)),
                      onExpansionChanged: (open) {
                        if (open) _readObject(o);
                      },
                      children: [for (final e in o.entries) _entryTile(e)],
                    ),
                ]),
    );
  }

  Widget _entryTile(OdEntry e) {
    final theme = Theme.of(context);
    final tags = [
      if (!e.readable) '只写',
      if (e.readable && !e.writable) '只读',
      if (e.stored) '可保存',
      if (e.needsIdle) '需停转',
    ];
    final err = _errors[e.key];
    return ListTile(
      dense: true,
      title: Text(e.name),
      subtitle: Text([e.address, ...tags].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(err ?? (e.readable ? e.format(_values[e.key]) : ''),
            style: err != null ? TextStyle(color: theme.colorScheme.error) : theme.textTheme.bodyLarge),
        if (e.writable) const Icon(Icons.edit, size: 18),
      ]),
      onTap: e.writable ? () => _edit(e) : null,
    );
  }
}

/// Asks for a new value of [e]: a choice for enums and booleans, a checked text field otherwise.
Future<Object?> askValue(BuildContext context, OdEntry e, Object? current) async {
  final choices = e.enums ?? (e.type.name == 'boolean' ? const ['否', '是'] : null);
  if (choices != null) {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(e.name),
        children: [
          for (var i = 0; i < choices.length; i++)
            if (e.check(i).error == null)
              SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text(choices[i])),
        ],
      ),
    );
    if (picked == null) return null;
    return e.type.name == 'boolean' ? picked == 1 : picked;
  }

  final controller = TextEditingController(text: current == null ? '' : e.format(current).split(' ').first);
  return showDialog<Object>(
    context: context,
    builder: (c) {
      String? error;
      return StatefulBuilder(builder: (c, setState) {
        void submit() {
          final r = e.parse(controller.text);
          if (r.error != null) {
            setState(() => error = r.error);
          } else {
            Navigator.pop(c, r.value);
          }
        }

        final (lo, hi) = e.range;
        return AlertDialog(
          title: Text(e.name),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: InputDecoration(
              suffixText: e.unit,
              helperText: lo.isFinite ? '范围 ${e.format(lo).split(' ').first} 到 ${e.format(hi).split(' ').first}' : null,
              errorText: error,
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: submit, child: const Text('写入')),
          ],
        );
      });
    },
  );
}
