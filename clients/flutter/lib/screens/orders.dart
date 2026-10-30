import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/discard_guard.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'receipts.dart';
import 'stock_documents.dart';

bool isLate(Object? due) {
  final d = DateTime.tryParse('$due');
  if (d == null) return false;
  final now = DateTime.now();
  return d.isBefore(DateTime(now.year, now.month, now.day));
}

Future<void> newPurchaseOrder(BuildContext context, Session session, {VoidCallback? onSaved}) async {
  final o = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => OrderEditorScreen(session: session)));
  onSaved?.call();
  if (o == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OrderScreen(session: session, id: o['id'] as int),
    ),
  );
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.session, this.supplierId});

  final Session session;
  final int? supplierId;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = true;

  Future<void> _new() => newPurchaseOrder(context, widget.session, onSaved: () => _list.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      key: _list,
      filtersActive: _open || _status != null,
      onClearFilters: () => setState(() {
        _open = false;
        _status = null;
      }),
      api: widget.session.api,
      path: '/api/purchase-orders',
      query: {'status': _status, 'open': _open ? true : null, 'supplierId': widget.supplierId},
      searchable: false,
      filters: [
        ChoiceFilter(label: 'Situação', value: _status, choices: orderStatuses, onChanged: (v) => setState(() => _status = v)),
        FilterChip(label: const Text('Somente abertos'), selected: _open, onSelected: (v) => setState(() => _open = v)),
      ],
      fab: widget.session.canBuy && widget.supplierId == null
          ? FloatingActionButton.extended(heroTag: 'new-po', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo pedido'))
          : null,
      columns: [
        col('Nº', 'number'),
        col('Fornecedor', 'supplierName'),
        dateCol('Emissão', 'issuedAt'),
        labelCol('Situação', 'status', orderStatuses),
        dateCol('Próxima entrega', 'nextDueDate'),
        col('Linhas', 'lineCount', numeric: true),
      ],
      rowColor: (_, e) => isLate(e['nextDueDate']) ? cs.errorContainer : null,
      onTap: (e) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderScreen(session: widget.session, id: e['id'] as int),
        ),
      ),
    );
  }
}

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Map<String, dynamic>? _o;
  String? _error;

  ApiClient get api => widget.session.api;
  String get base => '/api/purchase-orders/${widget.id}';
  bool get active => _o != null && (_o!['status'] == 'Open' || _o!['status'] == 'PartiallyReceived');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await api.get(base) as Map<String, dynamic>;
      if (mounted) setState(() => _o = o);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _reason(String action, String title) async {
    final reason = await promptText(context, title: title, label: 'Motivo', required: true);
    if (reason == null || !mounted) return;
    final r = await runAction(
      context,
      () => api.post('$base/$action', {'reason': reason}),
      success: action == 'cancel' ? 'Pedido cancelado' : 'Pedido encerrado',
    );
    if (r != null) setState(() => _o = r as Map<String, dynamic>);
  }

  Future<void> _reschedule(Map<String, dynamic> line) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Reprogramar linha ${line['lineNumber']}',
      fields: const [FieldSpec('dueDate', 'Nova data de entrega', type: FieldType.date, required: true)],
      initial: {'dueDate': line['dueDate']},
      submit: (b) => api.put('$base/lines/${line['id']}/due-date', b),
    );
    if (r != null) _load();
  }

  Future<void> _receive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiveScreen(session: widget.session, supplierId: _o!['supplierId'] as int, supplierName: '${_o!['supplierName']}'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final s = widget.session;
    final received = o != null && (o['lines'] as List).any((l) => (l['receivedQuantity'] as num) > 0);
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(o == null ? 'Pedido' : 'Pedido nº ${o['number']} · ${o['supplierName']}', overflow: TextOverflow.ellipsis),
          actions: [
            if (active && s.canReceive) TextButton.icon(onPressed: _receive, icon: const Icon(Icons.move_to_inbox), label: const Text('Receber NF')),
            if (active && s.canBuy)
              PopupMenuButton<String>(
                onSelected: (v) =>
                    v == 'cancel' ? _reason('cancel', 'Cancelar pedido nº ${o!['number']}') : _reason('close', 'Encerrar saldo do pedido nº ${o!['number']}'),
                itemBuilder: (_) => [
                  if (!received) const PopupMenuItem(value: 'cancel', child: Text('Cancelar pedido')),
                  if (received) const PopupMenuItem(value: 'close', child: Text('Encerrar saldo')),
                ],
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Itens'),
              Tab(text: 'Recebimentos'),
            ],
          ),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : o == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Section(
                        title: 'Pedido',
                        child: InfoGrid([
                          ('Situação', orderStatuses[o['status']] ?? fmt(o['status'])),
                          ('Fornecedor', fmt(o['supplierName'])),
                          ('Emitido', '${fmt(o['issuedBy'])} · ${fmtDate(o['issuedAt'])}'),
                          ('Condição', fmt(o['paymentTerms'])),
                          ('Total', fmtMoney(o['total'])),
                          ('Observações', fmt(o['notes'])),
                          ('Encerrado', o['closedBy'] == null ? '' : '${o['closedBy']} · ${fmtDate(o['closedAt'])} · ${fmt(o['closeReason'])}'),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Section(
                        title: 'Itens',
                        child: SimpleTable(
                          columns: [
                            col('Linha', 'lineNumber'),
                            col('Material', 'materialCode'),
                            col('Descrição', 'description'),
                            ColumnSpec('Quantidade', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
                            ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                            col('Desc. %', 'discountPercent', numeric: true),
                            col('IPI %', 'ipiPercent', numeric: true),
                            dateCol('Entrega', 'dueDate'),
                            col('Recebido', 'receivedQuantity', numeric: true),
                            col('Em aberto', 'openQuantity', numeric: true),
                            moneyCol('Total', 'total'),
                          ],
                          rows: (o['lines'] as List).cast<Map<String, dynamic>>(),
                          rowColor: (e) => (e['openQuantity'] as num) > 0 && isLate(e['dueDate']) ? cs.errorContainer : null,
                          actions: active && s.canBuy
                              ? (l) => [
                                  IconButton(
                                    tooltip: 'Reprogramar entrega',
                                    icon: const Icon(Icons.event_outlined, size: 20),
                                    onPressed: (l['openQuantity'] as num) > 0 ? () => _reschedule(l) : null,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                  ReceiptsView(session: s, query: {'purchaseOrderId': widget.id}),
                ],
              ),
      ),
    );
  }
}

const orderLineFields = [
  FieldSpec(
    'materialId',
    'Material',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/materials', fill: {'unit': 'purchaseUnit', 'description': 'description'}),
  ),
  FieldSpec('description', 'Descrição', hint: 'Obrigatória sem material'),
  FieldSpec('unit', 'Unidade'),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('unitPrice', 'Preço unitário', type: FieldType.decimal, required: true),
  FieldSpec('discountPercent', 'Desconto (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('dueDate', 'Entrega', type: FieldType.date, required: true),
];

num lineTotal(Map<String, dynamic> l) {
  num n(Object? v) => v is num ? v : 0;
  return n(l['quantity']) * n(l['unitPrice']) * (1 - n(l['discountPercent']) / 100) * (1 + n(l['ipiPercent']) / 100);
}

class OrderEditorScreen extends StatefulWidget {
  const OrderEditorScreen({super.key, required this.session});

  final Session session;

  @override
  State<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _OrderEditorScreenState extends State<OrderEditorScreen> {
  int? _supplierId;
  final _terms = TextEditingController();
  final _notes = TextEditingController();
  List<Map<String, dynamic>> _lines = [];
  String? _message;
  bool _busy = false;
  late final String _initial;

  String _signature() => jsonEncode([_supplierId, _terms.text, _notes.text, _lines]);

  @override
  void initState() {
    super.initState();
    _initial = _signature();
  }

  @override
  void dispose() {
    _terms.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_supplierId == null) return setState(() => _message = 'Informe o fornecedor');
    if (_lines.isEmpty) return setState(() => _message = 'Inclua ao menos uma linha');
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final o = await widget.session.api.post('/api/purchase-orders', {
        'supplierId': _supplierId,
        'paymentTerms': _terms.text.trim().isEmpty ? null : _terms.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'lines': [for (final l in _lines) zeroPercentsLine(stripLocal(l))],
      });
      if (mounted) Navigator.pop(context, o as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final w = wide ? 300.0 : double.infinity;
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Novo pedido de compra'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.check), label: const Text('Emitir')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: w,
                  child: LookupField(
                    api: widget.session.api,
                    spec: supplierLookup,
                    label: 'Fornecedor *',
                    value: _supplierId,
                    onChanged: (id, _) => setState(() => _supplierId = id),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: TextField(
                    controller: _terms,
                    decoration: const InputDecoration(labelText: 'Condição de pagamento', hintText: 'ex.: 28/56', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                SizedBox(
                  width: wide ? 500 : w,
                  child: TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinesEditor(
              api: widget.session.api,
              title: 'Itens',
              fields: orderLineFields,
              lines: _lines,
              onChanged: (l) => setState(() => _lines = l),
              columns: [
                ColumnSpec('Material', (e) => lbl(e, 'materialId')),
                col('Descrição', 'description'),
                ColumnSpec('Quantidade', (e) => '${fmt(e['quantity'])} ${e['unit'] ?? ''}', numeric: true),
                ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                dateCol('Entrega', 'dueDate'),
                ColumnSpec('Total', (e) => fmtMoney(lineTotal(e)), numeric: true),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Total: ${fmtMoney(_lines.fold<num>(0, (a, l) => a + lineTotal(l)))}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_message != null) Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> zeroPercentsLine(Map<String, dynamic> b) => {
  ...b,
  for (final k in ['discountPercent', 'icmsPercent', 'ipiPercent']) k: b[k] ?? 0,
};

class OverdueScreen extends StatelessWidget {
  const OverdueScreen({super.key, required this.session, this.supplierId});

  final Session session;
  final int? supplierId;

  @override
  Widget build(BuildContext context) => RecordList(
    api: session.api,
    path: '/api/purchasing/overdue',
    query: {'supplierId': supplierId},
    searchable: false,
    emptyText: 'Nenhuma entrega em atraso',
    columns: [
      col('Pedido', 'purchaseOrderNumber'),
      col('Linha', 'lineNumber'),
      col('Fornecedor', 'supplierName'),
      col('Descrição', 'description'),
      ColumnSpec('Qtd. pedida', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
      col('Recebido', 'receivedQuantity', numeric: true),
      col('Em aberto', 'openQuantity', numeric: true),
      dateCol('Entrega', 'dueDate'),
      col('Dias de atraso', 'daysLate', numeric: true),
    ],
    rowColor: (ctx, e) => (e['daysLate'] as num) > 15 ? Theme.of(ctx).colorScheme.errorContainer : null,
    onTap: (e) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderScreen(session: session, id: e['purchaseOrderId'] as int),
      ),
    ),
  );
}
