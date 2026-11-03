import 'package:flutter/material.dart';

/// Screens that share one sidebar entry: the entry opens the first tab, the others are reached from the strip above the screen.
class TabGroup {
  const TabGroup(this.section, this.title, this.icon, this.tabs);

  final String section;
  final String title;
  final IconData icon;
  final List<({String id, String label})> tabs;

  bool has(String id) => tabs.any((t) => t.id == id);
}

/// Strip of tabs above a screen of a [TabGroup]. A tab is a normal screen of the shell, so [onSelect] navigates and each tab keeps its own state.
class TabFrame extends StatelessWidget {
  const TabFrame({super.key, required this.tabs, required this.current, required this.onSelect, required this.child});

  final List<({String id, String label})> tabs;
  final String current;
  final ValueChanged<String> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Row(
          children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('tab-${t.id}'),
                  label: Text(t.label),
                  selected: t.id == current,
                  onSelected: (_) {
                    if (t.id != current) onSelect(t.id);
                  },
                ),
              ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}
