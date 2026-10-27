import 'dart:async';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';

class SearchTarget {
  const SearchTarget(this.id, this.icon, this.title, this.section);

  final String id;
  final IconData icon;
  final String title;
  final String section;
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

class GlobalSearch extends StatelessWidget {
  const GlobalSearch({
    super.key,
    required this.session,
    required this.controller,
    required this.targets,
    required this.onNavigate,
    required this.onOpenProduct,
    this.compact = false,
  });

  final Session session;
  final SearchController controller;
  final List<SearchTarget> targets;
  final void Function(String id) onNavigate;
  final void Function(int productId) onOpenProduct;
  final bool compact;

  Future<Iterable<Widget>> _suggestions(BuildContext context, SearchController c) async {
    final q = c.text.trim();
    final key = _fold(q);
    final screens = targets.where((t) => key.isEmpty || _fold(t.title).contains(key) || _fold(t.section).contains(key)).take(key.isEmpty ? 6 : 8).toList();
    final tiles = <Widget>[
      for (final t in screens)
        ListTile(
          leading: Icon(t.icon),
          title: Text(t.title),
          subtitle: t.section.isEmpty ? null : Text(t.section),
          onTap: () {
            c.closeView(null);
            onNavigate(t.id);
          },
        ),
    ];
    if (q.length >= 2) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (c.text.trim() != q) return tiles;
      try {
        final page = await session.api.list(products.path, q: q, take: 6);
        for (final p in page.items) {
          tiles.add(
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('${p['code']}  ${p['name']}'),
              subtitle: const Text('Produto'),
              onTap: () {
                c.closeView(null);
                onOpenProduct(p['id'] as int);
              },
            ),
          );
        }
      } catch (_) {}
    }
    if (tiles.isEmpty) tiles.add(const ListTile(title: Text('Nada encontrado')));
    return tiles;
  }

  @override
  Widget build(BuildContext context) => SearchAnchor(
    searchController: controller,
    viewHintText: 'Buscar telas e produtos',
    builder: (context, c) => compact
        ? IconButton(tooltip: 'Buscar (Ctrl+K)', onPressed: c.openView, icon: const Icon(Icons.search))
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, minWidth: 220),
            child: SearchBar(
              controller: c,
              hintText: 'Buscar telas e produtos (Ctrl+K)',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
              onTap: c.openView,
              onChanged: (_) => c.openView(),
            ),
          ),
    suggestionsBuilder: _suggestions,
  );
}

class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.session});

  final Session session;

  String get _initials {
    final name = (session.username ?? '?').trim();
    return name.isEmpty ? '?' : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Conta',
      offset: const Offset(0, 44),
      onSelected: (v) {
        if (v == 'logout') session.logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.username ?? '', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
              Text(session.role ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [Icon(Icons.logout, size: 20), SizedBox(width: 12), Text('Sair')]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(_initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
