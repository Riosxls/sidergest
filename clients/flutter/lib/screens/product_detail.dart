import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import 'where_used.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.session, required this.productId});

  final Session session;
  final int productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? _product;
  String? _error;

  ApiClient get api => widget.session.api;
  String get base => '/api/products/${widget.productId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _product = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _edit() async {
    final p = _product!;
    final result = await showEntityForm(
      context,
      api: api,
      title: 'Produto ${p['code']}',
      fields: products.fields,
      initial: p,
      readOnly: !widget.session.canWrite,
      onSubmit: (body) async => await api.put(base, body) as Map<String, dynamic>?,
      onDelete: () => api.delete(base),
    );
    if (result == null || !mounted) return;
    if (result['_deleted'] == true) {
      Navigator.pop(context);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(p == null ? 'Produto' : '${p['code']} · ${p['name']}', overflow: TextOverflow.ellipsis),
          actions: [if (p != null) IconButton(tooltip: 'Cadastro', onPressed: _edit, icon: const Icon(Icons.edit_outlined))],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Roteiro e estrutura'),
              Tab(text: 'Explosão'),
              Tab(text: 'Onde é usado'),
              Tab(text: 'Revisões'),
            ],
          ),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : p == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Summary(product: p),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RoutingTab(session: widget.session, productId: widget.productId, onChanged: _load),
                        ExplosionTab(api: api, productId: widget.productId),
                        WhereUsedView(session: widget.session, path: '$base/where-used'),
                        RevisionsTab(session: widget.session, productId: widget.productId, onChanged: _load),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final dims = p['shape'] == 'Circular'
        ? 'Ø ${fmt(p['diameterMm'])} × ${fmt(p['thicknessMm'])} × ${fmt(p['lengthMm'])} mm'
        : p['shape'] == 'Rectangular'
        ? '${fmt(p['widthMm'])} × ${fmt(p['heightMm'])} × ${fmt(p['thicknessMm'])} × ${fmt(p['lengthMm'])} mm'
        : null;
    final chips = <String>[
      kinds[p['kind']] ?? '',
      'NCM ${p['ncm']}',
      'Un. ${p['stockUnit']}',
      ?dims,
      if (p['netWeightKg'] != null) '${fmt(p['netWeightKg'])} kg',
      if (p['drawingRevision'] != null) 'Desenho rev. ${p['drawingRevision']}',
      if (p['processRevision'] != null) 'Processo rev. ${p['processRevision']}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (p['blocked'] == true)
            Chip(label: const Text('Bloqueado'), backgroundColor: Theme.of(context).colorScheme.errorContainer, visualDensity: VisualDensity.compact),
          for (final c in chips) Chip(label: Text(c), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}

class RoutingTab extends StatefulWidget {
  const RoutingTab({super.key, required this.session, required this.productId, required this.onChanged});

  final Session session;
  final int productId;
  final VoidCallback onChanged;

  @override
  State<RoutingTab> createState() => _RoutingTabState();
}

class _RoutingTabState extends State<RoutingTab> {
  List<Map<String, dynamic>>? _ops;
  Map<int, String> _opNames = {};
  String? _error;

  ApiClient get api => widget.session.api;
  bool get canWrite => widget.session.canWrite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([api.get('/api/products/${widget.productId}/routing'), if (_opNames.isEmpty) api.listAll('/api/standard-operations')]);
      if (!mounted) return;
      setState(() {
        _ops = (results[0] as List).cast<Map<String, dynamic>>();
        if (results.length > 1) _opNames = {for (final o in results[1] as List<Map<String, dynamic>>) o['id'] as int: o['name'] as String};
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _done(Map<String, dynamic>? result) async {
    if (result == null) return;
    await _load();
    widget.onChanged();
  }

  Future<void> _editOp([Map<String, dynamic>? op]) async {
    final next = (_ops ?? []).fold<int>(0, (m, o) => (o['sequence'] as int) > m ? o['sequence'] as int : m) + 10;
    _done(
      await showEntityForm(
        context,
        api: api,
        title: op == null ? 'Nova operação' : 'Operação ${op['sequence']}',
        fields: routingFields,
        initial: op ?? {'sequence': next},
        readOnly: !canWrite,
        onSubmit: (body) async =>
            (op == null ? await api.post('/api/products/${widget.productId}/routing', body) : await api.put('/api/routing-operations/${op['id']}', body))
                as Map<String, dynamic>?,
        onDelete: op == null ? null : () => api.delete('/api/routing-operations/${op['id']}'),
      ),
    );
  }

  Future<void> _editItem(Map<String, dynamic> op, [Map<String, dynamic>? item]) async {
    _done(
      await showEntityForm(
        context,
        api: api,
        title: item == null ? 'Novo item na operação ${op['sequence']}' : 'Item ${item['code']}',
        fields: bomItemFields,
        initial: item,
        readOnly: !canWrite,
        onSubmit: (body) async =>
            (item == null ? await api.post('/api/routing-operations/${op['id']}/items', body) : await api.put('/api/bom-items/${item['id']}', body))
                as Map<String, dynamic>?,
        onDelete: item == null ? null : () => api.delete('/api/bom-items/${item['id']}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final ops = _ops;
    if (ops == null) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(onPressed: () => _editOp(), icon: const Icon(Icons.add), label: const Text('Operação'))
          : null,
      body: ops.isEmpty
          ? const Center(child: Text('Sem operações no roteiro'))
          : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), children: [for (final op in ops) _opCard(op)]),
    );
  }

  Widget _opCard(Map<String, dynamic> op) {
    final theme = Theme.of(context);
    final items = (op['items'] as List).cast<Map<String, dynamic>>();
    final name = _opNames[op['standardOperationId']] ?? op['description'] ?? 'Operação ${op['sequence']}';
    final facts = [
      if (op['machineCode'] != null) 'Máquina ${op['machineCode']}',
      if (op['setupHours'] != null) 'Setup ${fmt(op['setupHours'])} h',
      if (op['piecesPerHour'] != null) '${fmt(op['piecesPerHour'])} pç/h',
      if (op['operators'] != null) '${fmt(op['operators'])} oper.',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${op['sequence']}', style: const TextStyle(fontSize: 13))),
              title: Text(name, style: theme.textTheme.titleMedium),
              subtitle: facts.isEmpty ? null : Text(facts),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canWrite) IconButton(tooltip: 'Adicionar item', icon: const Icon(Icons.playlist_add), onPressed: () => _editItem(op)),
                  IconButton(tooltip: 'Editar operação', icon: const Icon(Icons.edit_outlined), onPressed: () => _editOp(op)),
                ],
              ),
            ),
            for (final it in items)
              InkWell(
                onTap: () => _editItem(op, it),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(52, 6, 12, 6),
                  child: Row(
                    children: [
                      Icon(
                        it['materialId'] != null ? Icons.inventory_2_outlined : Icons.precision_manufacturing_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${it['code']}  ${it['description']}', overflow: TextOverflow.ellipsis)),
                      Text('${fmt(it['quantity'])} ${it['unit']}${it['factor'] != 1 ? ' × ${fmt(it['factor'])}' : ''}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ExplosionTab extends StatefulWidget {
  const ExplosionTab({super.key, required this.api, required this.productId});

  final ApiClient api;
  final int productId;

  @override
  State<ExplosionTab> createState() => _ExplosionTabState();
}

class _ExplosionTabState extends State<ExplosionTab> {
  final _qty = TextEditingController(text: '1');
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = parseDecimal(_qty.text.trim());
    if (q == null || q <= 0) return setState(() => _error = 'Quantidade inválida');
    setState(() => _loading = true);
    try {
      final r = await widget.api.get('/api/products/${widget.productId}/bom/explode', {'quantity': q});
      if (mounted) {
        setState(() {
          _result = r as Map<String, dynamic>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = null;
          _error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    final lines = (r?['lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final mats = (r?['materials'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final tree = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Estrutura (${lines.length} linhas)', style: theme.textTheme.titleSmall),
        ),
        for (final l in lines)
          Padding(
            padding: EdgeInsets.fromLTRB(8.0 + 20.0 * ((l['level'] as int) - 1), 4, 8, 4),
            child: Row(
              children: [
                Icon(l['materialId'] != null ? Icons.inventory_2_outlined : Icons.subdirectory_arrow_right, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text('${l['code']}  ${l['description']}', overflow: TextOverflow.ellipsis)),
                Text('Op ${l['operationSequence']}  ', style: theme.textTheme.bodySmall),
                Text('${fmt(l['totalQuantity'])} ${l['unit']}'),
              ],
            ),
          ),
      ],
    );
    final totals = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Necessidade de materiais', style: theme.textTheme.titleSmall),
        ),
        for (final m in mats)
          ListTile(
            dense: true,
            title: Text('${m['code']}  ${m['description']}'),
            trailing: Text('${fmt(m['totalQuantity'])} ${m['unit']}', style: theme.textTheme.titleSmall),
          ),
        if (mats.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nenhum material')),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  key: const ValueKey('explode-qty'),
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantidade', isDense: true, border: OutlineInputBorder()),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _loading ? null : _run, icon: const Icon(Icons.account_tree_outlined), label: const Text('Explodir')),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (r != null)
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: tree),
                      const VerticalDivider(),
                      Expanded(flex: 2, child: totals),
                    ],
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Materiais'),
                            Tab(text: 'Estrutura'),
                          ],
                        ),
                        Expanded(child: TabBarView(children: [totals, tree])),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

class RevisionsTab extends StatefulWidget {
  const RevisionsTab({super.key, required this.session, required this.productId, required this.onChanged});

  final Session session;
  final int productId;
  final VoidCallback onChanged;

  @override
  State<RevisionsTab> createState() => _RevisionsTabState();
}

class _RevisionsTabState extends State<RevisionsTab> {
  late Future<List<Map<String, dynamic>>> _future = _fetch();

  String get path => '/api/products/${widget.productId}/revisions';

  Future<List<Map<String, dynamic>>> _fetch() async => ((await widget.session.api.get(path)) as List).cast<Map<String, dynamic>>();

  Future<void> _add() async {
    final r = await showEntityForm(
      context,
      api: widget.session.api,
      title: 'Nova revisão',
      fields: revisionFields,
      onSubmit: (body) async => await widget.session.api.post(path, body) as Map<String, dynamic>?,
    );
    if (r == null) return;
    setState(() {
      _future = _fetch();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: widget.session.canWrite
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Revisão'))
          : null,
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('Sem revisões'));
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final at = DateTime.parse(r['createdAt'] as String).toLocal();
              final when =
                  '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text('${revisionKinds[r['kind']] ?? r['kind']} rev. ${r['code']}'),
                subtitle: Text([when, r['user'], r['reason']].whereType<String>().join(' · ')),
              );
            },
          );
        },
      ),
    );
  }
}
