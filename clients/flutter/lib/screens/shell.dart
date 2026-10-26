import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import 'dashboard.dart';
import 'entity_list.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows ? 1 : 0;

  List<(IconData, String)> get _destinations => [(Icons.dashboard_outlined, 'Painel'), for (final s in masterData) (s.icon, s.title)];

  Widget _page() => _index == 0
      ? DashboardScreen(key: const ValueKey('dashboard'), session: widget.session)
      : EntityListScreen(key: ValueKey(masterData[_index - 1].path), session: widget.session, spec: masterData[_index - 1]);

  Widget _menu({bool closeDrawer = false}) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      for (final (i, d) in _destinations.indexed) ...[
        if (i == 3 || i == 5 || i == 7) const Divider(),
        ListTile(
          dense: true,
          leading: Icon(d.$1),
          title: Text(d.$2),
          selected: i == _index,
          onTap: () {
            setState(() => _index = i);
            if (closeDrawer) Navigator.pop(context);
          },
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_index].$2),
        actions: [
          Center(child: Text('${s.username} · ${s.role}')),
          IconButton(tooltip: 'Sair', onPressed: s.logout, icon: const Icon(Icons.logout)),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
      body: wide
          ? Row(
              children: [
                SizedBox(width: 240, child: _menu()),
                const VerticalDivider(width: 1),
                Expanded(child: _page()),
              ],
            )
          : _page(),
    );
  }
}
