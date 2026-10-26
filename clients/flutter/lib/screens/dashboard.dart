import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import 'product_detail.dart';

class DashboardData {
  DashboardData(this.counts, this.products);

  final Map<EntitySpec, int> counts;
  final List<Map<String, dynamic>> products;

  List<Map<String, dynamic>> get withoutRouting => products.where((p) => (p['operationCount'] ?? 0) == 0).toList();
  List<Map<String, dynamic>> get blocked => products.where((p) => p['blocked'] == true).toList();

  Map<String, int> countBy(String Function(Map<String, dynamic>) key) {
    final m = <String, int>{};
    for (final p in products) {
      m.update(key(p), (v) => v + 1, ifAbsent: () => 1);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _future = _fetch();

  static final _counted = [products, materials, machines, standardOperations, workCenters, tools];

  Future<DashboardData> _fetch() async {
    final api = widget.session.api;
    final pages = await Future.wait(_counted.map((s) => api.list(s.path, take: 1)));
    final all = await api.listAll(products.path);
    return DashboardData({for (var i = 0; i < _counted.length; i++) _counted[i]: pages[i].total}, all);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  void _open(Map<String, dynamic> p) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(session: widget.session, productId: p['id'] as int),
        ),
      )
      .then((_) => _refresh());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${snap.error}'),
                TextButton(onPressed: _refresh, child: const Text('Tentar novamente')),
              ],
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final width = MediaQuery.sizeOf(context).width;
        final panelWidth = width >= 1200 ? (width - 120) / 3 : (width >= 800 ? (width - 100) / 2 : width - 32);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in d.counts.entries) _StatCard(icon: e.key.icon, label: e.key.title, value: e.value),
                  _StatCard(icon: Icons.block, label: 'Produtos bloqueados', value: d.blocked.length, alert: d.blocked.isNotEmpty),
                  _StatCard(icon: Icons.warning_amber, label: 'Produtos sem roteiro', value: d.withoutRouting.length, alert: d.withoutRouting.isNotEmpty),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: panelWidth,
                    child: _BarPanel(title: 'Produtos por tipo', data: d.countBy((p) => kinds[p['kind']] ?? '—')),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _BarPanel(title: 'Produtos por formato', data: d.countBy((p) => shapes[p['shape']] ?? 'Sem formato')),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _BarPanel(title: 'Operações por produto', data: d.countBy((p) => _bucket(p['operationCount'] as int? ?? 0))),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _ProductPanel(title: 'Sem roteiro', items: d.withoutRouting, onTap: _open),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _ProductPanel(title: 'Bloqueados', items: d.blocked, onTap: _open),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _bucket(int n) => n == 0
      ? '0'
      : n <= 3
      ? '1–3'
      : n <= 6
      ? '4–6'
      : '7+';
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, this.alert = false});

  final IconData icon;
  final String label;
  final int value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        color: alert ? cs.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: alert ? cs.onErrorContainer : cs.primary),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.headlineMedium),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarPanel extends StatelessWidget {
  const _BarPanel({required this.title, required this.data});

  final String title;
  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = data.values.fold<int>(1, (m, v) => v > m ? v : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (data.isEmpty) const Text('Sem dados'),
            for (final e in data.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 110, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 16,
                            width: c.maxWidth * e.value / max,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 48, child: Text('${e.value}', textAlign: TextAlign.right)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductPanel extends StatelessWidget {
  const _ProductPanel({required this.title, required this.items, required this.onTap});

  final String title;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$title (${items.length})', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum')),
            for (final p in items.take(8))
              ListTile(
                dense: true,
                title: Text('${p['code']}  ${p['name']}', overflow: TextOverflow.ellipsis),
                onTap: () => onTap(p),
              ),
            if (items.length > 8) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('+ ${items.length - 8}')),
          ],
        ),
      ),
    );
  }
}
