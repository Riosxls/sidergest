import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities.dart';
import '../session.dart';

class SearchTarget {
  const SearchTarget(this.id, this.icon, this.title, this.section);

  final String id;
  final IconData icon;
  final String title;
  final String section;
}

class RecentItem {
  const RecentItem(this.type, this.id, this.title);

  final String type;
  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'type': type, 'id': id, 'title': title};

  static RecentItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = j['type'], id = j['id'], title = j['title'];
    if (type is! String || id is! String || title is! String) return null;
    return RecentItem(type, id, title);
  }
}

class RecentStore {
  static const _key = 'recentItems';
  static const max = 6;

  static Future<List<RecentItem>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(_key) ?? '[]');
      return [if (raw is List) ...raw.map(RecentItem.fromJson).whereType<RecentItem>()];
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }

  static Future<void> add(RecentItem item) async {
    try {
      final list = await load();
      list.removeWhere((e) => e.type == item.type && e.id == item.id);
      list.insert(0, item);
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final e in list.take(max)) e.toJson()]));
    } catch (_) {}
  }
}

String fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

class PaletteAction {
  const PaletteAction(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final void Function() run;
}

class _Entry {
  const _Entry(this.group, this.icon, this.title, this.subtitle, this.run);

  final String group;
  final IconData icon;
  final String title;
  final String? subtitle;
  final void Function() run;
}

class SearchLauncher extends StatelessWidget {
  const SearchLauncher({super.key, required this.onOpen, this.compact = false});

  final VoidCallback onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (compact) return IconButton(tooltip: 'Buscar (Ctrl+K)', onPressed: onOpen, icon: const Icon(Icons.search));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 220),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Buscar telas, ações e produtos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Ctrl K', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCommandPalette(
  BuildContext context, {
  required Session session,
  required List<SearchTarget> targets,
  required List<PaletteAction> actions,
  required void Function(String id) onNavigate,
  required void Function(int productId) onOpenProduct,
}) async {
  final recents = await RecentStore.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _Palette(session: session, targets: targets, actions: actions, recents: recents, onNavigate: onNavigate, onOpenProduct: onOpenProduct),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({
    required this.session,
    required this.targets,
    required this.actions,
    required this.recents,
    required this.onNavigate,
    required this.onOpenProduct,
  });

  final Session session;
  final List<SearchTarget> targets;
  final List<PaletteAction> actions;
  final List<RecentItem> recents;
  final void Function(String id) onNavigate;
  final void Function(int productId) onOpenProduct;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  static const _rowHeight = 52.0;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _q = '';
  int _index = 0;
  int _request = 0;
  List<Map<String, dynamic>> _products = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close(VoidCallback run) {
    Navigator.of(context).pop();
    run();
  }

  void _onChanged(String v) {
    setState(() {
      _q = v.trim();
      _index = 0;
    });
    _debounce?.cancel();
    final q = _q;
    if (q.length < 2) {
      setState(() => _products = []);
      return;
    }
    final req = ++_request;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final page = await widget.session.api.list(products.path, q: q, take: 6);
        if (mounted && req == _request) setState(() => _products = page.items);
      } catch (_) {
        if (mounted && req == _request) setState(() => _products = []);
      }
    });
  }

  List<_Entry> _entries() {
    final key = fold(_q);
    bool hit(String s) => key.isEmpty || fold(s).contains(key);
    final titleOf = {for (final t in widget.targets) t.id: t};
    final out = <_Entry>[];
    for (final a in widget.actions.where((a) => hit(a.label))) {
      out.add(_Entry('Ações', a.icon, a.label, null, () => _close(a.run)));
    }
    if (key.isEmpty) {
      for (final r in widget.recents) {
        if (r.type == 'screen') {
          final t = titleOf[r.id];
          if (t != null) out.add(_Entry('Recentes', t.icon, t.title, t.section.isEmpty ? null : t.section, () => _close(() => widget.onNavigate(t.id))));
        } else if (r.type == 'product') {
          final id = int.tryParse(r.id);
          if (id != null) out.add(_Entry('Recentes', Icons.inventory_2_outlined, r.title, 'Produto', () => _close(() => widget.onOpenProduct(id))));
        }
      }
    } else {
      for (final t in widget.targets.where((t) => hit(t.title) || hit(t.section)).take(8)) {
        out.add(_Entry('Telas', t.icon, t.title, t.section.isEmpty ? null : t.section, () => _close(() => widget.onNavigate(t.id))));
      }
      for (final p in _products) {
        final id = p['id'] as int;
        final title = '${p['code']}  ${p['name']}';
        out.add(
          _Entry('Produtos', Icons.inventory_2_outlined, title, 'Produto', () {
            RecentStore.add(RecentItem('product', '$id', title));
            _close(() => widget.onOpenProduct(id));
          }),
        );
      }
    }
    if (key.isEmpty && out.every((e) => e.group == 'Ações')) {
      for (final t in widget.targets.take(6)) {
        out.add(_Entry('Telas', t.icon, t.title, t.section.isEmpty ? null : t.section, () => _close(() => widget.onNavigate(t.id))));
      }
    }
    return out;
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + delta) % count);
    final top = _index * _rowHeight;
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = _entries();
    if (_index >= entries.length) _index = entries.isEmpty ? 0 : entries.length - 1;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: Focus(
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
            if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
              _move(1, entries.length);
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
              _move(entries.length - 1, entries.length);
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
              if (entries.isNotEmpty) entries[_index].run();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Digite uma tela, ação ou produto', border: OutlineInputBorder()),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: entries.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Nada encontrado'))
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          final selected = i == _index;
                          final first = i == 0 || entries[i - 1].group != e.group;
                          return Material(
                            color: selected ? cs.secondaryContainer : Colors.transparent,
                            child: InkWell(
                              onTap: e.run,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Icon(e.icon, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (e.subtitle != null)
                                            Text(
                                              e.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (first) Text(e.group, style: theme.textTheme.labelSmall?.copyWith(color: cs.primary)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
