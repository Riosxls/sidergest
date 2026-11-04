import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/discard_guard.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart' show confirmStep;
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'purchasing_path.dart';
import 'quotations.dart';
import 'receipts.dart';
import 'requisitions.dart';
import 'stock_documents.dart';
import 'suppliers.dart';

bool isLate(Object? due) {
  final d = DateTime.tryParse('$due');
  if (d == null) return false;
  final now = DateTime.now();
  return d.isBefore(DateTime(now.year, now.month, now.day));
}

/// New purchase order; pass [supplierId] and [supplierName] to start it for that supplier.
Future<void> newPurchaseOrder(BuildContext context, Session session, {VoidCallback? onSaved, int? supplierId, String? supplierName}) async {
  final o = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(builder: (_) => OrderEditorScreen(session: session, supplierId: supplierId, supplierName: supplierName)),
  );
  onSaved?.call();
  if (o == null || !context.mounted) return;
  await openPurchaseOrder(context, session, o['id'] as int);
}

/// Purchase orders list (Suprimentos).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.session, this.supplierId, this.supplierName});

  final Session session;
  final int? supplierId;

  /// Name of [supplierId], shown in the editor when a new order starts from the supplier's page.
  final String? supplierName;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status;
  bool _open = true;

  Future<void> _new() => newPurchaseOrder(
    context,
    widget.session,
    onSaved: () => _list.currentState?.reload(),
    supplierId: widget.supplierId,
    supplierName: widget.supplierName,
  );

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
      // A chosen status wins over "Somente abertos": "Encerrado" next to "open" would always be empty.
      query: {'status': _status, 'open': _open && _status == null ? true : null, 'supplierId': widget.supplierId},
      searchable: false,
      filters: [
        ChoiceFilter(label: 'Situação', value: _status, choices: orderStatuses, onChanged: (v) => setState(() => _status = v)),
        Tooltip(
          message: _status == null ? '' : 'A situação escolhida já define quais pedidos aparecem',
          child: FilterChip(label: const Text('Somente abertos'), selected: _open && _status == null, onSelected: _status == null ? (v) => setState(() => _open = v) : null),
        ),
      ],
      fab: widget.session.canBuy
          ? FloatingActionButton.extended(heroTag: 'new-po', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo pedido'))
          : null,
      columns: [
        col('Nº', 'number'),
        col('Fornecedor', 'supplierName'),
        dateCol('Emissão', 'issuedAt'),
        labelCol('Situação', 'status', orderStatuses),
        // The tint alone is not enough (colour blindness, print): late rows also say so.
        ColumnSpec('Próxima entrega', (e) => isLate(e['nextDueDate']) ? '${fmtDay(e['nextDueDate'])} · Atrasado' : fmtDay(e['nextDueDate'])),
        col('Linhas', 'lineCount', numeric: true),
      ],
      rowColor: (_, e) => isLate(e['nextDueDate']) ? cs.errorContainer : null,
      onTap: (e) => openPurchaseOrder(context, widget.session, e['id'] as int),
    );
  }
}

/// Purchase order detail.
Future<void> openPurchaseOrder(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'purchase-order', id, (_) => OrderScreen(session: session, id: id));

/// Same as [openPurchaseOrder], in the place of the page that calls it (a quotation whose last winner just got its order).
Future<void> replaceWithPurchaseOrder(BuildContext context, Session session, int id) =>
    replaceRecord<void>(context, 'purchase-order', id, (_) => OrderScreen(session: session, id: id));

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
      if (mounted) {
        setState(() {
          _o = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _reason(String action, String title) async {
    final reason = await promptText(context, title: title, label: 'Motivo', required: true, confirmLabel: action == 'cancel' ? 'Cancelar pedido' : 'Encerrar saldo', danger: true);
    if (reason == null || !mounted) return;
    final r = await runAction(
      context,
      () => api.post('$base/$action', {'reason': reason}),
      success: action == 'cancel' ? 'Pedido cancelado' : 'Pedido encerrado',
    );
    if (r != null && mounted) setState(() => _o = r as Map<String, dynamic>);
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
    if (r != null) unawaited(_load());
  }

  Future<void> _receive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiveScreen(session: widget.session, supplierId: _o!['supplierId'] as int, supplierName: '${_o!['supplierName']}', purchaseOrderId: widget.id),
      ),
    );
    if (mounted) unawaited(_load());
  }

  VoidCallback? get _quotationLink => _o?['quotationId'] == null ? null : () => openQuotation(context, widget.session, _o!['quotationId'] as int).then((_) => _load());

  VoidCallback? get _requisitionLink =>
      purchasingLink(context, 'Abrir qual requisição?', 'Requisição nº', _o?['requisitions'] as List?, (id) => openRequisition(context, widget.session, id));

  VoidCallback? get _receiptLink => purchasingLink(context, 'Abrir qual recebimento?', 'Recebimento nº', _o?['receipts'] as List?, (id) => openReceipt(context, widget.session, id));

  /// The purchase stage path above the tabs: the order is stage 3 of 4, or 4 once something arrived.
  Widget _withPath(Map<String, dynamic> o, Widget tabs) {
    final status = o['status'];
    final (step, failed) = switch (status) {
      'Cancelled' => (2, 'Cancelado'),
      'PartiallyReceived' || 'Received' || 'Closed' => (3, null),
      _ => (2, null),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: PurchasingPath(current: step, page: 2, failedLabel: failed, requisition: _requisitionLink, quotation: _quotationLink, receipt: _receiptLink),
        ),
        Expanded(child: tabs),
      ],
    );
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
            if (o != null)
              RelatedMenu(
                links: [
                  if (o['supplierId'] is int) RelatedLink(Icons.business_outlined, 'Fornecedor: ${o['supplierName']}', () => openSupplier(context, s, o['supplierId'] as int)),
                  if (o['quotationId'] != null) RelatedLink(Icons.request_quote_outlined, 'Cotação nº ${o['quotationNumber']}', _quotationLink!),
                  for (final r in ((o['requisitions'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    RelatedLink(Icons.assignment_outlined, 'Requisição nº ${r['number']}', () => openRequisition(context, s, r['id'] as int)),
                  for (final r in ((o['receipts'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    RelatedLink(Icons.move_to_inbox_outlined, 'Recebimento nº ${r['number']}', () => openReceipt(context, s, r['id'] as int)),
                ],
              ),
            if (active && s.canReceive) TextButton.icon(onPressed: _receive, icon: const Icon(Icons.move_to_inbox), label: const Text('Receber NF')),
            // Receiving is the one primary action; cancelling and closing the balance are rare and sit in the overflow menu.
            if (active && s.canBuy)
              PopupMenuButton<String>(
                key: const ValueKey('order-menu'),
                tooltip: 'Mais ações',
                onSelected: (v) => v == 'cancel' ? _reason('cancel', 'Cancelar pedido nº ${o!['number']}') : _reason('close', 'Encerrar saldo do pedido nº ${o!['number']}'),
                itemBuilder: (_) => [
                  if (!received)
                    const PopupMenuItem(value: 'cancel', key: ValueKey('order-cancel'), child: ListTile(leading: Icon(Icons.block), title: Text('Cancelar pedido'))),
                  if (received)
                    const PopupMenuItem(value: 'close', key: ValueKey('order-close'), child: ListTile(leading: Icon(Icons.playlist_remove), title: Text('Encerrar saldo'))),
                ],
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: o == null ? 'Itens' : 'Itens (${(o['lines'] as List).length})'),
              Tab(text: o == null ? 'Recebimentos' : 'Recebimentos (${((o['receipts'] as List?) ?? const []).length})'),
            ],
          ),
        ),
        body: _error != null
            ? LoadError(message: _error!, onRetry: _load)
            : o == null
            ? const Center(child: CircularProgressIndicator())
            : _withPath(o, TabBarView(
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
                            ColumnSpec('Entrega', (e) => (e['openQuantity'] as num) > 0 && isLate(e['dueDate']) ? '${fmtDay(e['dueDate'])} · Atrasado' : fmtDay(e['dueDate'])),
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
              )),
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
  FieldSpec('dueDate', 'Entrega', type: FieldType.date, required: true),
  // Empty means 0 (see zeroPercentsLine); folded until a line has a discount or taxes.
  FieldSpec('discountPercent', 'Desconto (%)', type: FieldType.decimal, advanced: true),
  FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, advanced: true),
  FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, advanced: true),
];

num lineTotal(Map<String, dynamic> l) {
  num n(Object? v) => v is num ? v : 0;
  return n(l['quantity']) * n(l['unitPrice']) * (1 - n(l['discountPercent']) / 100) * (1 + n(l['ipiPercent']) / 100);
}

/// Editor for a purchase order.
class OrderEditorScreen extends StatefulWidget {
  const OrderEditorScreen({super.key, required this.session, this.supplierId, this.supplierName});

  final Session session;

  /// A supplier chosen before the editor opened (from the supplier's own page); it cannot be changed there.
  final int? supplierId;
  final String? supplierName;

  @override
  State<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _OrderEditorScreenState extends State<OrderEditorScreen> {
  late int? _supplierId = widget.supplierId;
  late String? _supplierName = widget.supplierName;
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
    final total = _lines.fold<num>(0, (a, l) => a + lineTotal(l));
    final ok = await confirmStep(
      context,
      title: 'Emitir o pedido de compra?',
      message: '${_supplierName ?? 'O fornecedor'} · ${_lines.length} ${_lines.length == 1 ? 'linha' : 'linhas'} · ${fmtMoney(total)}. Depois de emitido, só dá para reprogramar entregas, cancelar ou encerrar.',
      confirmLabel: 'Emitir pedido',
      icon: Icons.receipt_long_outlined,
    );
    if (!ok || !mounted) return;
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
                    initialDisplay: widget.supplierName,
                    enabled: widget.supplierId == null,
                    onChanged: (id, entity) => setState(() {
                      _supplierId = id;
                      _supplierName = entity == null ? null : '${entity['name']}';
                    }),
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

/// Overdue purchase orders, optionally limited to one supplier.
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
    onTap: (e) => openPurchaseOrder(context, session, e['purchaseOrderId'] as int),
  );
}
