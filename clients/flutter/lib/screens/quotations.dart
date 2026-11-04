import 'dart:async';
import 'dart:math' as math;
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
import '../widgets/responsive.dart';
import 'orders.dart';
import 'purchasing_path.dart';
import 'requisitions.dart';
import 'suppliers.dart';

/// Purchasing quotations list.
class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key, required this.session});

  final Session session;

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status = 'Open';

  void _open(int id) => openQuotation(context, widget.session, id)
      .then((_) => _list.currentState?.reload());

  Future<void> _new() async {
    final q = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewQuotationDialog(api: widget.session.api),
    );
    unawaited(_list.currentState?.reload());
    if (q != null && mounted) _open(q['id'] as int);
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/quotations',
    query: {'status': _status},
    searchable: false,
    filters: [ChoiceFilter(label: 'Situação', value: _status, choices: quotationStatuses, onChanged: (v) => setState(() => _status = v))],
    fab: widget.session.canBuy
        ? FloatingActionButton.extended(heroTag: 'new-quote', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nova cotação'))
        : null,
    columns: [
      col('Nº', 'number'),
      dateCol('Data', 'createdAt'),
      labelCol('Situação', 'status', quotationStatuses),
      col('Itens', 'itemCount', numeric: true),
      col('Fornecedores', 'supplierCount', numeric: true),
    ],
    onTap: (e) async => _open(e['id'] as int),
  );
}

/// Dialog that starts a purchasing quotation.
class NewQuotationDialog extends StatefulWidget {
  const NewQuotationDialog({super.key, required this.api, this.initialRequisitionIds = const {}});

  final ApiClient api;

  /// Requisitions already ticked when the dialog opens (the one the user came from).
  final Set<int> initialRequisitionIds;

  @override
  State<NewQuotationDialog> createState() => _NewQuotationDialogState();
}

class _NewQuotationDialogState extends State<NewQuotationDialog> {
  List<Map<String, dynamic>>? _reqs;
  late final _selected = <int>{...widget.initialRequisitionIds};
  final _suppliers = <int, String>{};
  final _notes = TextEditingController();
  String? _message;
  bool _busy = false;

  /// True once the user ticked or typed something that closing the dialog would lose.
  bool get _touched => _suppliers.isNotEmpty || _notes.text.trim().isNotEmpty || _selected.difference(widget.initialRequisitionIds).isNotEmpty;

  Future<void> _cancel() async {
    if (_touched && !await confirmDiscard(context)) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    widget.api
        .listAll('/api/requisitions', query: {'status': 'Approved'})
        .then((l) => mounted ? setState(() => _reqs = l) : null, onError: (e) => mounted ? setState(() => _message = friendlyError(e)) : null);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addSupplier() async {
    final s = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LookupPicker(api: widget.api, path: '/api/suppliers', title: 'Fornecedor'),
    );
    if (s != null) setState(() => _suppliers[s['id'] as int] = '${s['name']}');
  }

  Future<void> _create() async {
    if (_selected.isEmpty || _suppliers.isEmpty) return setState(() => _message = 'Selecione requisições e fornecedores');
    setState(() => _busy = true);
    try {
      final q = await widget.api.post('/api/quotations', {
        'requisitionIds': _selected.toList(),
        'supplierIds': _suppliers.keys.toList(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, q as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqs = _reqs;
    return AlertDialog(
      title: const Text('Nova cotação'),
      content: SizedBox(
        width: dialogWidth(context, 640),
        height: math.min(520, MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Requisições aprovadas (${_selected.length} marcadas)', style: Theme.of(context).textTheme.titleSmall)),
                if (reqs != null && reqs.isNotEmpty)
                  TextButton(
                    key: const ValueKey('quote-select-all'),
                    onPressed: () => setState(() {
                      if (_selected.length >= reqs.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(reqs.map((r) => r['id'] as int));
                      }
                    }),
                    child: Text(_selected.length >= reqs.length ? 'Limpar seleção' : 'Marcar todas'),
                  ),
              ],
            ),
            Expanded(
              child: reqs == null
                  ? const Center(child: CircularProgressIndicator())
                  : reqs.isEmpty
                  ? const Center(child: Text('Nenhuma requisição aprovada aguardando cotação'))
                  : ListView(
                      children: [
                        for (final r in reqs)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(r['id']),
                            title: Text('${r['number']} · ${r['description']}'),
                            subtitle: Text(
                              '${fmt(r['approvedQuantity'] ?? r['quantity'])} ${r['unit']}${r['neededBy'] == null ? '' : ' · até ${fmtDay(r['neededBy'])}'}${r['department'] == null ? '' : ' · ${r['department']}'}',
                            ),
                            onChanged: (v) => setState(() => v == true ? _selected.add(r['id'] as int) : _selected.remove(r['id'])),
                          ),
                      ],
                    ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Fornecedores (${_suppliers.length})', style: Theme.of(context).textTheme.titleSmall)),
                TextButton.icon(
                  key: const ValueKey('quote-add-supplier'),
                  onPressed: _addSupplier,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [for (final e in _suppliers.entries) InputChip(label: Text(e.value), onDeleted: () => setState(() => _suppliers.remove(e.key)))],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Observações', isDense: true, border: OutlineInputBorder()),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('quote-create'), onPressed: _busy ? null : _create, child: const Text('Criar cotação')),
      ],
    );
  }
}

const bidFields = [
  FieldSpec('unitPrice', 'Preço unitário', type: FieldType.decimal, required: true),
  FieldSpec('leadTimeDays', 'Prazo de entrega (dias)', type: FieldType.integer),
  // Empty means 0 (see zeroPercents); they stay folded until the supplier quotes a discount or taxes.
  FieldSpec('discountPercent', 'Desconto (%)', type: FieldType.decimal, advanced: true),
  FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, advanced: true),
  FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, advanced: true),
  FieldSpec('paymentTerms', 'Condição de pagamento', advanced: true),
  FieldSpec('notes', 'Observações', advanced: true),
];

Map<String, dynamic> zeroPercents(Map<String, dynamic> b) => {
  ...b,
  for (final k in ['discountPercent', 'icmsPercent', 'ipiPercent']) k: b[k] ?? 0,
};

/// Purchasing quotation detail.
Future<void> openQuotation(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'quotation', id, (_) => QuotationScreen(session: session, id: id));

class QuotationScreen extends StatefulWidget {
  const QuotationScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<QuotationScreen> createState() => _QuotationScreenState();
}

class _QuotationScreenState extends State<QuotationScreen> {
  Map<String, dynamic>? _q;
  List<Map<String, dynamic>> _cmp = [];
  String? _error;

  ApiClient get api => widget.session.api;
  String get base => '/api/quotations/${widget.id}';
  bool get open => _q?['status'] == 'Open' && widget.session.canBuy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.get(base), api.get('$base/comparison')]);
      if (mounted) {
        setState(() {
          _q = r[0] as Map<String, dynamic>;
          _cmp = (r[1] as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  List<Map<String, dynamic>> get _items => ((_q?['items'] as List?) ?? []).cast<Map<String, dynamic>>();

  /// Requisition number to id, for the "Req. 12" links.
  Map<int, int> get _requisitionIds => {
    for (final r in ((_q?['requisitions'] as List?) ?? const []).cast<Map<String, dynamic>>()) r['number'] as int: r['id'] as int,
  };

  Map<int, String> get _supplierNames => {
    for (final i in _items)
      for (final b in (i['bids'] as List).cast<Map<String, dynamic>>()) b['supplierId'] as int: '${b['supplierName']}',
  };

  Future<void> _call(Future<dynamic> Function() f, [String? msg]) async {
    final r = await runAction(context, f, success: msg);
    if (r != null) await _load();
  }

  Future<void> _editBid(Map<String, dynamic> item, Map<String, dynamic> bid) async {
    final r = await submitForm(
      context,
      api: api,
      title: '${bid['supplierName']} · item ${item['item']}',
      fields: bidFields,
      // A 0 is the same as empty, so it does not unfold the folded percent fields.
      initial: {
        ...bid,
        for (final k in ['discountPercent', 'icmsPercent', 'ipiPercent'])
          if (bid[k] == 0) k: null,
      },
      submit: (b) => api.put('$base/bids/${bid['id']}', zeroPercents(b)),
    );
    if (r != null) await _load();
  }

  Future<void> _addSupplier() async {
    final s = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LookupPicker(api: api, path: '/api/suppliers', title: 'Fornecedor'),
    );
    if (s != null) await _call(() => api.post('$base/suppliers', {'supplierId': s['id']}), 'Fornecedor incluído');
  }

  /// Suppliers that won an item and have no order from this quotation yet.
  Map<int, String> get _unorderedWinners {
    final ordered = ((_q?['orderedSupplierIds'] as List?) ?? const []).cast<int>().toSet();
    final winners = <int, String>{};
    for (final i in _items) {
      for (final b in (i['bids'] as List).cast<Map<String, dynamic>>()) {
        if (b['status'] == 'Approved' && !ordered.contains(b['supplierId'])) winners[b['supplierId'] as int] = '${b['supplierName']}';
      }
    }
    return winners;
  }

  Future<void> _order() async {
    final winners = _unorderedWinners;
    if (winners.isEmpty) return showError(context, 'Todos os fornecedores vencedores já têm pedido');
    int? supplierId;
    if (winners.length == 1) {
      supplierId = winners.keys.first;
      final ok = await confirmStep(
        context,
        title: 'Gerar pedido para ${winners.values.first}?',
        message: 'Os itens que esse fornecedor venceu na cotação nº ${_q!['number']} viram um pedido de compra.',
        confirmLabel: 'Gerar pedido',
        icon: Icons.receipt_long_outlined,
      );
      if (!ok || !mounted) return;
    } else {
      supplierId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Gerar pedido para'),
          children: [for (final w in winners.entries) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, w.key), child: Text(w.value))],
        ),
      );
    }
    if (supplierId == null || !mounted) return;
    final o = await runAction(context, () => api.post('/api/purchase-orders/from-quotation', {'quotationId': widget.id, 'supplierId': supplierId}));
    if (o == null || !mounted) return;
    // The last winner's order ends this quotation's work: the order takes its place, so Back does not return to a finished page.
    if (winners.length == 1) {
      await replaceWithPurchaseOrder(context, widget.session, o['id'] as int);
    } else {
      await openPurchaseOrder(context, widget.session, o['id'] as int);
    }
    if (mounted) unawaited(_load());
  }

  VoidCallback? get _requisitionLink => purchasingLink(context, 'Abrir qual requisição?', 'Requisição nº', _q?['requisitions'] as List?, (id) => openRequisition(context, widget.session, id));

  VoidCallback? get _orderLink => purchasingLink(context, 'Abrir qual pedido?', 'Pedido nº', _q?['orders'] as List?, (id) => openPurchaseOrder(context, widget.session, id).then((_) => _load()));

  /// Awarding an item closes it to other suppliers and cannot be undone here, so it names the supplier and the total first.
  Future<void> _award(Map<String, dynamic> item, Map<String, dynamic> bid) async {
    final ok = await confirmStep(
      context,
      title: 'Aprovar a proposta de ${bid['supplierName']}?',
      message: 'Item ${item['item']} · ${item['description']}\nTotal: ${fmtMoney(bid['lineTotal'])}. As outras propostas deste item ficam reprovadas.',
      confirmLabel: 'Aprovar proposta',
      icon: Icons.thumb_up_alt_outlined,
    );
    if (!ok || !mounted) return;
    await _call(() => api.post('$base/items/${item['itemId']}/award', {'bidId': bid['bidId']}), 'Proposta de ${bid['supplierName']} aprovada');
  }

  Future<void> _rejectItem(Map<String, dynamic> item) async {
    final ok = await confirmStep(
      context,
      title: 'Reprovar o item ${item['item']}?',
      message: 'Nenhuma proposta deste item será aprovada e as requisições dele voltam como cotação reprovada.',
      confirmLabel: 'Reprovar item',
      icon: Icons.thumb_down_alt_outlined,
      cancelLabel: 'Voltar',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _call(() => api.post('$base/items/${item['itemId']}/reject', {}), 'Item reprovado');
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'Cancelar a cotação nº ${_q!['number']}?', confirmLabel: 'Cancelar cotação', cancelLabel: 'Manter cotação', danger: true)) return;
    await _call(() => api.post('$base/cancel', {}), 'Cotação cancelada');
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    // Hidden once every winner has its order, so the button is not a dead end.
    final hasWinner = _unorderedWinners.isNotEmpty;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(q == null ? 'Cotação' : 'Cotação nº ${q['number']} · ${quotationStatuses[q['status']]}'),
          actions: [
            if (q != null)
              RelatedMenu(
                links: [
                  for (final r in ((q['requisitions'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    RelatedLink(Icons.assignment_outlined, 'Requisição nº ${r['number']}', () => openRequisition(context, widget.session, r['id'] as int)),
                  for (final o in ((q['orders'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    RelatedLink(Icons.receipt_long_outlined, 'Pedido nº ${o['number']}', () => openPurchaseOrder(context, widget.session, o['id'] as int).then((_) => _load())),
                  for (final e in _supplierNames.entries)
                    RelatedLink(Icons.business_outlined, 'Fornecedor: ${e.value}', () => openSupplier(context, widget.session, e.key)),
                ],
              ),
            if (q != null && q['status'] != 'Cancelled' && hasWinner && widget.session.canBuy)
              TextButton.icon(key: const ValueKey('quote-order'), onPressed: _order, icon: const Icon(Icons.receipt_long), label: const Text('Gerar pedido')),
            if (open)
              PopupMenuButton<String>(
                key: const ValueKey('quote-menu'),
                tooltip: 'Mais ações',
                onSelected: (v) => v == 'supplier' ? _addSupplier() : _cancel(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'supplier', key: ValueKey('quote-add-supplier-item'), child: ListTile(leading: Icon(Icons.person_add_alt), title: Text('Adicionar fornecedor'))),
                  PopupMenuItem(value: 'cancel', key: ValueKey('quote-cancel-item'), child: ListTile(leading: Icon(Icons.cancel_outlined), title: Text('Cancelar cotação'))),
                ],
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Propostas (${_items.length})'),
              Tab(text: 'Comparativo (${_cmp.length})'),
            ],
          ),
        ),
        body: _error != null
            ? LoadError(message: _error!, onRetry: _load)
            : q == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: PurchasingPath(
                      current: 1,
                      page: 1,
                      failedLabel: q['status'] == 'Cancelled' ? 'Cancelada' : null,
                      requisition: _requisitionLink,
                      order: _orderLink,
                    ),
                  ),
                  Expanded(child: TabBarView(children: [_bids(), _comparison()])),
                ],
              ),
      ),
    );
  }

  Widget _bids() => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final i in _items) ...[
          Section(
            title: 'Item ${i['item']} · ${i['materialCode'] ?? ''} ${i['description']} · ${fmt(i['quantity'])} ${i['unit']}',
            actions: [
              // Each requisition number opens its page.
              for (final n in (i['requisitionNumbers'] as List))
                if (_requisitionIds[n] != null)
                  TextButton(onPressed: () => openRequisition(context, widget.session, _requisitionIds[n]!), child: Text('Req. $n'))
                else
                  Text('Req. $n'),
            ],
            child: SimpleTable(
              columns: [
                col('Fornecedor', 'supplierName'),
                ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                col('Desc. %', 'discountPercent', numeric: true),
                col('ICMS %', 'icmsPercent', numeric: true),
                col('IPI %', 'ipiPercent', numeric: true),
                col('Prazo (dias)', 'leadTimeDays', numeric: true),
                col('Condição', 'paymentTerms'),
                ColumnSpec('Situação', (e) => e['unitPrice'] == null ? 'Sem resposta' : (bidStatuses[e['status']] ?? '')),
              ],
              rows: (i['bids'] as List).cast<Map<String, dynamic>>(),
              rowColor: (e) => e['status'] == 'Approved' ? Theme.of(context).colorScheme.primaryContainer : null,
              actions: open
                  ? (b) => [
                      IconButton(
                        key: ValueKey('bid-${b['id']}'),
                        tooltip: b['status'] == 'Pending' ? 'Registrar proposta' : 'Proposta já decidida: não dá para alterar',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: b['status'] == 'Pending' ? () => _editBid(i, b) : null,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );

  Widget _comparison() {
    final names = _supplierNames;
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final c in _cmp) ...[
            Builder(
              builder: (context) {
                final bids = (c['bids'] as List).cast<Map<String, dynamic>>();
                final decided = bids.any((b) => b['status'] == 'Approved');
                final pending = (c['pendingSupplierIds'] as List).map((id) => names[id] ?? '#$id').join(', ');
                return Section(
                  title: 'Item ${c['item']} · ${c['description']} · ${fmt(c['quantity'])} ${c['unit']}',
                  actions: [
                    if (open && !decided && bids.isNotEmpty)
                      TextButton(
                        onPressed: () => _rejectItem(c),
                        child: const Text('Reprovar item'),
                      ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoGrid([
                        (
                          'Última compra',
                          c['lastUnitPrice'] == null
                              ? 'Sem histórico'
                              : '${fmtNum(c['lastUnitPrice'], 4)} · ${fmtDay(c['lastPurchaseDate'])} · ${c['lastSupplierName']}',
                        ),
                        ('Sem resposta', pending),
                      ]),
                      const SizedBox(height: 8),
                      SimpleTable(
                        columns: [
                          ColumnSpec('#', (e) => '${e['rank']}º'),
                          col('Fornecedor', 'supplierName'),
                          ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                          ColumnSpec('Líquido', (e) => fmtNum(e['netUnitPrice'], 4), numeric: true),
                          ColumnSpec('Com IPI', (e) => fmtNum(e['landedUnitPrice'], 4), numeric: true),
                          ColumnSpec('vs. última', (e) => _vsLast(e['landedUnitPrice'], c['lastUnitPrice']), numeric: true),
                          moneyCol('Total', 'lineTotal'),
                          col('Prazo (dias)', 'leadTimeDays', numeric: true),
                          col('Condição', 'paymentTerms'),
                          labelCol('Situação', 'status', bidStatuses),
                        ],
                        rows: bids,
                        actionsFirst: true,
                        rowColor: (e) => e['status'] == 'Approved' ? cs.primaryContainer : (e['rank'] == 1 && !decided ? cs.secondaryContainer : null),
                        actions: open && !decided
                            ? (b) => [
                                FilledButton.tonal(
                                  key: ValueKey('award-${b['bidId']}'),
                                  onPressed: () => _award(c, b),
                                  child: const Text('Aprovar'),
                                ),
                              ]
                            : null,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  static String _vsLast(Object? price, Object? last) {
    if (price is! num || last is! num || last == 0) return '';
    final d = (price - last) / last * 100;
    return '${d >= 0 ? '+' : ''}${fmtNum(d, 1)} %';
  }
}
