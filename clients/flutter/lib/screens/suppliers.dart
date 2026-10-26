import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'orders.dart';
import 'receipts.dart';
import 'stock_documents.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _list = GlobalKey<RecordListState>();

  Future<void> _new() async {
    final r = await showEntityForm(
      context,
      api: widget.session.api,
      title: 'Novo fornecedor',
      fields: suppliers.fields,
      onSubmit: (b) async => await widget.session.api.post(suppliers.path, b) as Map<String, dynamic>?,
    );
    if (r != null) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: suppliers.path,
    columns: suppliers.columns,
    searchHint: 'Nome, fantasia ou código antigo',
    fab: widget.session.canWrite
        ? FloatingActionButton.extended(heroTag: 'new-sup', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo'))
        : null,
    onTap: (e) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierScreen(session: widget.session, supplier: e),
      ),
    ),
  );
}

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key, required this.session, required this.supplier});

  final Session session;
  final Map<String, dynamic> supplier;

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  late Map<String, dynamic> _s = widget.supplier;
  int get id => _s['id'] as int;

  Future<void> _edit() async {
    final r = await showEntityForm(
      context,
      api: widget.session.api,
      title: 'Fornecedor',
      fields: suppliers.fields,
      initial: _s,
      readOnly: !widget.session.canWrite,
      onSubmit: (b) async => await widget.session.api.put('${suppliers.path}/$id', b) as Map<String, dynamic>?,
    );
    if (r != null && r['_deleted'] != true && r['id'] != null) setState(() => _s = r);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_s['name']}', overflow: TextOverflow.ellipsis),
          actions: [IconButton(tooltip: 'Cadastro', onPressed: _edit, icon: const Icon(Icons.edit_outlined))],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Desempenho'),
              Tab(text: 'Materiais'),
              Tab(text: 'Atrasos'),
              Tab(text: 'Pedidos'),
              Tab(text: 'Recebimentos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PerformanceView(session: s, supplierId: id),
            _SupplierMaterials(session: s, supplierId: id),
            OverdueScreen(session: s, supplierId: id),
            OrdersScreen(session: s, supplierId: id),
            ReceiptsView(session: s, query: {'supplierId': id}),
          ],
        ),
      ),
    );
  }
}

class PerformanceView extends StatefulWidget {
  const PerformanceView({super.key, required this.session, required this.supplierId});

  final Session session;
  final int supplierId;

  @override
  State<PerformanceView> createState() => _PerformanceViewState();
}

class _PerformanceViewState extends State<PerformanceView> {
  int _months = 12;
  late Future<dynamic> _future = _fetch();

  Future<dynamic> _fetch() {
    final now = DateTime.now();
    return widget.session.api.get('/api/suppliers/${widget.supplierId}/performance', {
      'from': isoDate(DateTime(now.year, now.month - _months, now.day)),
      'to': isoDate(now),
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3 meses')),
              ButtonSegment(value: 6, label: Text('6 meses')),
              ButtonSegment(value: 12, label: Text('12 meses')),
              ButtonSegment(value: 36, label: Text('36 meses')),
            ],
            selected: {_months},
            onSelectionChanged: (v) => setState(() {
              _months = v.first;
              _future = _fetch();
            }),
          ),
        ),
        const SizedBox(height: 12),
        FutureView<dynamic>(
          key: ValueKey(_months),
          future: _future,
          builder: (context, p) {
            final pct = (p['onTimePercent'] as num).toDouble();
            final color = p['receivedLines'] == 0 ? cs.outline : (pct >= 90 ? Colors.green : (pct >= 70 ? Colors.orange : cs.error));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Section(
                  title: 'Pontualidade',
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 96,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(value: pct / 100, strokeWidth: 10, color: color, backgroundColor: cs.surfaceContainerHighest),
                            Center(child: Text('${fmtNum(pct, 1)} %', style: Theme.of(context).textTheme.titleMedium)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: InfoGrid([
                          ('Linhas recebidas', fmt(p['receivedLines'])),
                          ('No prazo', fmt(p['onTimeLines'])),
                          ('Atraso médio', '${fmtNum(p['averageDaysLate'], 1)} dias'),
                          ('Linhas em atraso hoje', fmt(p['overdueLines'])),
                        ]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Section(
                  title: 'Volume',
                  child: InfoGrid([
                    ('Pedidos', fmt(p['orders'])),
                    ('Pedidos abertos', fmt(p['openOrders'])),
                    ('Valor pedido', fmtMoney(p['orderedValue'])),
                    ('Recebimentos', fmt(p['receipts'])),
                    ('Valor recebido', fmtMoney(p['receivedValue'])),
                  ]),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SupplierMaterials extends StatefulWidget {
  const _SupplierMaterials({required this.session, required this.supplierId});

  final Session session;
  final int supplierId;

  @override
  State<_SupplierMaterials> createState() => _SupplierMaterialsState();
}

class _SupplierMaterialsState extends State<_SupplierMaterials> {
  final _list = GlobalKey<RecordListState>();

  Future<void> _edit([Map<String, dynamic>? current]) async {
    final s = widget.session;
    final r = await showEntityForm(
      context,
      api: s.api,
      title: current == null ? 'Vincular material' : '${current['materialCode']} · ${current['materialDescription']}',
      fields: [
        if (current == null) const FieldSpec('materialId', 'Material', type: FieldType.lookup, lookup: materialLookup, required: true),
        const FieldSpec('qualification', 'Qualificação', hint: 'ex.: A, B, C'),
        const FieldSpec('qualifiedAt', 'Qualificado em', type: FieldType.date),
        const FieldSpec('notes', 'Observações'),
      ],
      initial: current,
      readOnly: !s.canBuy,
      onSubmit: (b) async =>
          await s.api.put('/api/suppliers/${widget.supplierId}/materials/${current?['materialId'] ?? b['materialId']}', b) as Map<String, dynamic>?,
      onDelete: current == null ? null : () => s.api.delete('/api/suppliers/${widget.supplierId}/materials/${current['materialId']}'),
    );
    if (r != null) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/suppliers/${widget.supplierId}/materials',
    searchable: false,
    fab: widget.session.canBuy
        ? FloatingActionButton.extended(heroTag: 'new-sm', onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Vincular material'))
        : null,
    columns: [
      col('Material', 'materialCode'),
      col('Descrição', 'materialDescription'),
      col('Qualificação', 'qualification'),
      dateCol('Qualificado em', 'qualifiedAt'),
      ColumnSpec('Último preço', (e) => fmtNum(e['lastUnitPrice'], 4), numeric: true),
      dateCol('Última compra', 'lastPurchaseDate'),
      col('Observações', 'notes'),
    ],
    onTap: (e) => _edit(e),
  );
}
