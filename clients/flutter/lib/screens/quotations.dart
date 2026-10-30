import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'orders.dart';

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key, required this.session});

  final Session session;

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _status = 'Open';

  void _open(int id) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => QuotationScreen(session: widget.session, id: id),
        ),
      )
      .then((_) => _list.currentState?.reload());

  Future<void> _new() async {
    final q = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewQuotationDialog(api: widget.session.api),
    );
    _list.currentState?.reload();
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

class NewQuotationDialog extends StatefulWidget {
  const NewQuotationDialog({super.key, required this.api});

  final ApiClient api;

  @override
  State<NewQuotationDialog> createState() => _NewQuotationDialogState();
}

class _NewQuotationDialogState extends State<NewQuotationDialog> {
  List<Map<String, dynamic>>? _reqs;
  final _selected = <int>{};
  final _suppliers = <int, String>{};
  final _notes = TextEditingController();
  String? _message;
  bool _busy = false;

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
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
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
        width: 640,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Requisições aprovadas', style: Theme.of(context).textTheme.titleSmall),
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
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('quote-create'), onPressed: _busy ? null : _create, child: const Text('Criar cotação')),
      ],
    );
  }
}

const bidFields = [
  FieldSpec('unitPrice', 'Preço unitário', type: FieldType.decimal, required: true),
  FieldSpec('discountPercent', 'Desconto (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('icmsPercent', 'ICMS (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('ipiPercent', 'IPI (%)', type: FieldType.decimal, defaultValue: 0),
  FieldSpec('leadTimeDays', 'Prazo de entrega (dias)', type: FieldType.integer),
  FieldSpec('paymentTerms', 'Condição de pagamento'),
  FieldSpec('notes', 'Observações'),
];

Map<String, dynamic> zeroPercents(Map<String, dynamic> b) => {
  ...b,
  for (final k in ['discountPercent', 'icmsPercent', 'ipiPercent']) k: b[k] ?? 0,
};

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
      initial: bid['unitPrice'] == null ? {...bid, 'discountPercent': 0, 'icmsPercent': 0, 'ipiPercent': 0} : bid,
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

  Future<void> _order() async {
    final winners = <int, String>{};
    for (final i in _items) {
      for (final b in (i['bids'] as List).cast<Map<String, dynamic>>()) {
        if (b['status'] == 'Approved') winners[b['supplierId'] as int] = '${b['supplierName']}';
      }
    }
    if (winners.isEmpty) return showError(context, 'Nenhuma proposta aprovada');
    final supplierId = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Gerar pedido para'),
        children: [for (final w in winners.entries) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, w.key), child: Text(w.value))],
      ),
    );
    if (supplierId == null || !mounted) return;
    final o = await runAction(context, () => api.post('/api/purchase-orders/from-quotation', {'quotationId': widget.id, 'supplierId': supplierId}));
    if (o == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderScreen(session: widget.session, id: o['id'] as int),
      ),
    );
    _load();
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'Cancelar a cotação nº ${_q!['number']}?')) return;
    await _call(() => api.post('$base/cancel', {}), 'Cotação cancelada');
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final hasWinner = _items.any((i) => (i['bids'] as List).any((b) => b['status'] == 'Approved'));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(q == null ? 'Cotação' : 'Cotação nº ${q['number']} · ${quotationStatuses[q['status']]}'),
          actions: [
            if (open) IconButton(tooltip: 'Adicionar fornecedor', onPressed: _addSupplier, icon: const Icon(Icons.person_add_alt)),
            if (q != null && q['status'] != 'Cancelled' && hasWinner && widget.session.canBuy)
              TextButton.icon(key: const ValueKey('quote-order'), onPressed: _order, icon: const Icon(Icons.receipt_long), label: const Text('Gerar pedido')),
            if (open) IconButton(tooltip: 'Cancelar cotação', onPressed: _cancel, icon: const Icon(Icons.cancel_outlined)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Propostas'),
              Tab(text: 'Comparativo'),
            ],
          ),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : q == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_bids(), _comparison()]),
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
            actions: [if ((i['requisitionNumbers'] as List).isNotEmpty) Text('Req. ${(i['requisitionNumbers'] as List).join(', ')}')],
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
                        tooltip: 'Registrar proposta',
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
                        onPressed: () => _call(() => api.post('$base/items/${c['itemId']}/reject', {}), 'Item reprovado'),
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
                                  onPressed: () => _call(
                                    () => api.post('$base/items/${c['itemId']}/award', {'bidId': b['bidId']}),
                                    'Proposta de ${b['supplierName']} aprovada',
                                  ),
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
