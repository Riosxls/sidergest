import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screens that share one sidebar entry: the entry opens the first tab, the others are reached from the strip above the screen.
class TabGroup {
  const TabGroup(this.section, this.title, this.icon, this.tabs);

  final String section;
  final String title;
  final IconData icon;
  final List<({String id, String label})> tabs;

  bool has(String id) => tabs.any((t) => t.id == id);

  /// The name of a tab when it differs from the group's own ("Expedição" > "Certificados"), else null.
  String? tabLabel(String id) {
    for (final t in tabs) {
      if (t.id == id) return t.label == title ? null : t.label;
    }
    return null;
  }
}

/// Strip of tabs of a [TabGroup]. A tab is a normal screen of the shell, so [onSelect] navigates and each tab keeps its own state.
/// The selected chip scrolls into view (a phone shows only three or four), and Left / Right move between the tabs.
class TabStrip extends StatefulWidget {
  const TabStrip({super.key, required this.tabs, required this.current, required this.onSelect});

  final List<({String id, String label})> tabs;
  final String current;
  final ValueChanged<String> onSelect;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _chips = <String, GlobalKey>{};

  GlobalKey _key(String id) => _chips.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(TabStrip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current || old.tabs.length != widget.tabs.length) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = _chips[widget.current]?.currentContext;
    if (mounted && c != null && c.mounted) unawaited(Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 180)));
  });

  void _step(int delta) {
    final i = widget.tabs.indexWhere((t) => t.id == widget.current);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= widget.tabs.length) return;
    widget.onSelect(widget.tabs[j].id);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Abas',
    child: FocusTraversalGroup(
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1), const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1)},
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Row(
            children: [
              for (final t in widget.tabs)
                Padding(
                  key: _key(t.id),
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('tab-${t.id}'),
                    label: Text(t.label),
                    selected: t.id == widget.current,
                    onSelected: (_) {
                      if (t.id != widget.current) widget.onSelect(t.id);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
