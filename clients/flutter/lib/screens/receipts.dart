import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/discard_guard.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'orders.dart';
import 'purchasing_path.dart';
import 'quotations.dart';
import 'requisitions.dart';
import 'stock_documents.dart';
import 'suppliers.dart';

/// Goods receipts list. Give [supplierId] and [supplierName] (with [allowNew]) to start a receipt for that supplier.
class ReceiptsView extends StatefulWidget {
  const ReceiptsView({super.key, required this.session, this.query = const {}, this.allowNew = false, this.supplierId, this.supplierName});

  final Session session;
  final Map<String, dynamic> query;
  final bool allowNew;
  final int? supplierId;
  final String? supplierName;

  @override
  State<ReceiptsView> createState() => _ReceiptsViewState();
}

class _ReceiptsViewState extends State<ReceiptsView> {
  final _list = GlobalKey<RecordListState>();

  Future<void> _new() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiveScreen(session: widget.session, supplierId: widget.supplierId, supplierName: widget.supplierName)),
    );
    unawaited(_list.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/goods-receipts',
    query: widget.query,
    searchable: false,
    fab: widget.allowNew && widget.session.canReceive
        ? FloatingActionButton.extended(heroTag: 'new-gr', onPressed: _new, icon: const Icon(Icons.move_to_inbox), label: const Text('Receber NF'))
        : null,
    columns: [
      col('Nº', 'number'),
      ColumnSpec('NF', (e) => '${e['invoiceNumber']}${(e['invoiceSeries'] as String? ?? '').isEmpty ? '' : '-${e['invoiceSeries']}'}'),
      col('Fornecedor', 'supplierName'),
      dateCol('Data NF', 'invoiceDate'),
      ColumnSpec('Recebido em', (e) => fmtDate(e['receivedAt'])),
      moneyCol('Total', 'calculatedTotal'),
      ColumnSpec('Divergente', (e) => e['divergent'] == true ? 'Sim' : ''),
    ],
    rowColor: (ctx, e) => e['divergent'] == true ? Theme.of(ctx).colorScheme.tertiaryContainer : null,
    onTap: (e) => openReceipt(context, widget.session, e['id'] as int),
  );
}

/// Goods receipt detail.
Future<void> openReceipt(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'receipt', id, (_) => ReceiptScreen(session: session, id: id));

/// Same as [openReceipt], in the place of the page that calls it (the form that has just registered it).
Future<void> replaceWithReceipt(BuildContext context, Session session, int id) =>
    replaceRecord<void>(context, 'receipt', id, (_) => ReceiptScreen(session: session, id: id));

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Map<String, dynamic>? _r;
  String? _error;

  /// The orders the receipt was made against (for the links to their quotations and requisitions); optional context.
  List<Map<String, dynamic>> _orders = const [];

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await s.api.get('/api/goods-receipts/${widget.id}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
      });
      unawaited(_loadOrders(r));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _loadOrders(Map<String, dynamic> r) async {
    final ids = {for (final l in (r['lines'] as List).cast<Map<String, dynamic>>()) l['purchaseOrderId'] as int};
    try {
      final orders = await Future.wait(ids.map((id) => s.api.get('/api/purchase-orders/$id')));
      if (mounted) setState(() => _orders = orders.cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('receipts: Optional context; the page works without the quotation and requisition links: $e');
    }
  }

  /// Distinct orders of the lines, as `{id, number}` maps.
  List<Map<String, dynamic>> get _lineOrders {
    final seen = <int, Map<String, dynamic>>{};
    for (final l in ((_r?['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      seen[l['purchaseOrderId'] as int] = {'id': l['purchaseOrderId'], 'number': l['purchaseOrderNumber']};
    }
    return seen.values.toList();
  }

  List<Map<String, dynamic>> _fromOrders(String key) {
    final seen = <int, Map<String, dynamic>>{};
    for (final o in _orders) {
      for (final x in ((o[key] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        seen[x['id'] as int] = x;
      }
    }
    return seen.values.toList();
  }

  VoidCallback? get _orderLink => purchasingLink(context, 'Abrir qual pedido?', 'Pedido nº', _lineOrders, (id) => openPurchaseOrder(context, s, id));

  VoidCallback? get _requisitionLink => purchasingLink(context, 'Abrir qual requisição?', 'Requisição nº', _fromOrders('requisitions'), (id) => openRequisition(context, s, id));

  VoidCallback? get _quotationLink {
    final seen = <int, Map<String, dynamic>>{
      for (final o in _orders)
        if (o['quotationId'] != null) o['quotationId'] as int: {'id': o['quotationId'], 'number': o['quotationNumber']},
    };
    return purchasingLink(context, 'Abrir qual cotação?', 'Cotação nº', seen.values.toList(), (id) => openQuotation(context, s, id));
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? 'Recebimento' : 'Recebimento nº ${r['number']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (r != null)
            RelatedMenu(
              links: [
                RelatedLink(Icons.business_outlined, 'Fornecedor: ${r['supplierName']}', () => openSupplier(context, s, r['supplierId'] as int)),
                for (final o in _lineOrders) RelatedLink(Icons.receipt_long_outlined, 'Pedido nº ${o['number']}', () => openPurchaseOrder(context, s, o['id'] as int)),
              ],
            ),
        ],
      ),
      body: _error != null && r == null
          ? LoadError(message: _error!, onRetry: _load)
          : r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PurchasingPath(current: 3, page: 3, requisition: _requisitionLink, quotation: _quotationLink, order: _orderLink),
                const SizedBox(height: 12),
                Section(
                  title: 'NF ${r['invoiceNumber']}${((r['invoiceSeries'] as String?) ?? '').isEmpty ? '' : '-${r['invoiceSeries']}'} · ${r['supplierName']}',
                  child: InfoGrid([
                    ('Recebimento', '${r['number']}'),
                    ('Data NF', fmtDay(r['invoiceDate'])),
                    ('Recebido', '${fmt(r['receivedBy'])} · ${fmtDate(r['receivedAt'])}'),
                    ('Total calculado', fmtMoney(r['calculatedTotal'])),
                    ('Total da NF', fmtMoney(r['invoiceTotal'])),
                    ('Divergência', r['divergent'] == true ? 'Sim · ${fmt(r['divergenceJustification'])}' : 'Não'),
                    ('Observações', fmt(r['notes'])),
                  ]),
                ),
                const SizedBox(height: 12),
                Section(
                  title: 'Itens',
                  child: SimpleTable(
                    columns: [
                      col('Pedido', 'purchaseOrderNumber'),
                      col('Material', 'materialCode'),
                      col('Descrição', 'description'),
                      ColumnSpec('Quantidade', (e) => '${fmt(e['quantity'])} ${e['unit']}', numeric: true),
                      ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                      col('IPI %', 'ipiPercent', numeric: true),
                      moneyCol('Total', 'total'),
                      col('Lote', 'lotCode'),
                    ],
                    rows: (r['lines'] as List).cast<Map<String, dynamic>>(),
                    actions: (l) => [
                      IconButton(
                        tooltip: 'Abrir pedido nº ${l['purchaseOrderNumber']}',
                        icon: const Icon(Icons.open_in_new, size: 20),
                        onPressed: () => openPurchaseOrder(context, s, l['purchaseOrderId'] as int),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Section(
                  title: 'Parcelas a pagar',
                  child: SimpleTable(
                    columns: [col('Parcela', 'sequence'), dateCol('Vencimento', 'dueDate'), moneyCol('Valor', 'amount')],
                    rows: (r['installments'] as List).cast<Map<String, dynamic>>(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OpenLine {
  _OpenLine(this.order, this.line) : price = TextEditingController(text: fmt(line['unitPrice']));

  final Map<String, dynamic> order;
  final Map<String, dynamic> line;
  final qty = TextEditingController();
  final TextEditingController price;
  final lot = TextEditingController();

  num? get quantity => qty.text.trim().isEmpty ? null : parseDecimal(qty.text.trim());

  /// "Pedido 12/3", to name the line in a message.
  String get label => 'Pedido ${order['number']}/${line['lineNumber']}';

  num total() {
    final q = quantity ?? 0;
    final p = parseDecimal(price.text.trim()) ?? 0;
    final t = q * p * (1 - (line['discountPercent'] as num) / 100) * (1 + (line['ipiPercent'] as num) / 100);
    return (t * 100).round() / 100;
  }

  void dispose() {
    qty.dispose();
    price.dispose();
    lot.dispose();
  }
}

/// Form to receive goods into stock, optionally for one supplier. [purchaseOrderId] is the order the user came from: its lines come first.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.session, this.supplierId, this.supplierName, this.purchaseOrderId});

  final Session session;
  final int? supplierId;
  final String? supplierName;
  final int? purchaseOrderId;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late int? _supplierId = widget.supplierId;
  late String? _supplierName = widget.supplierName;
  final _invoice = TextEditingController();
  final _series = TextEditingController();
  final _date = TextEditingController(text: fmtDay(isoDate(DateTime.now())));
  final _invoiceTotal = TextEditingController();
  final _justification = TextEditingController();
  final _notes = TextEditingController();
  List<_OpenLine> _lines = [];
  bool _loading = false;
  bool _busy = false;
  String? _message;
  late final String _initial;

  /// Counts the order loads; only the latest one may fill the lines (a slow answer for a supplier no longer chosen is dropped).
  int _loadToken = 0;
  int _supplierEpoch = 0;

  String _signature() => jsonEncode([
    _supplierId, _invoice.text, _series.text, _date.text, _invoiceTotal.text, _justification.text, _notes.text,
    [for (final l in _lines) if (l.qty.text.isNotEmpty || l.lot.text.isNotEmpty) [_lines.indexOf(l), l.qty.text, l.price.text, l.lot.text]],
  ]);

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _initial = _signature();
    if (_supplierId != null) _loadOrders();
  }

  @override
  void dispose() {
    for (final c in [_invoice, _series, _date, _invoiceTotal, _justification, _notes]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final token = ++_loadToken;
    final supplier = _supplierId;
    setState(() {
      _loading = true;
      _message = null;
      _lines = [];
    });
    try {
      final orders = await api.listAll('/api/purchase-orders', query: {'supplierId': supplier, 'open': true});
      final details = await Future.wait(orders.map((o) => api.get('/api/purchase-orders/${o['id']}')));
      final lines = <_OpenLine>[
        for (final d in details.cast<Map<String, dynamic>>())
          for (final l in (d['lines'] as List).cast<Map<String, dynamic>>())
            if (l['closed'] != true && (l['openQuantity'] as num) > 0) _OpenLine(d, l),
      ];
      // The order the user came from first, then by due date.
      int rank(_OpenLine l) => l.order['id'] == widget.purchaseOrderId ? 0 : 1;
      lines.sort((a, b) {
        final byOrder = rank(a).compareTo(rank(b));
        return byOrder != 0 ? byOrder : '${a.line['dueDate']}'.compareTo('${b.line['dueDate']}');
      });
      if (!mounted || token != _loadToken) {
        for (final l in lines) {
          l.dispose();
        }
        return;
      }
      setState(() => _lines = lines);
    } catch (e) {
      if (mounted && token == _loadToken) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted && token == _loadToken) setState(() => _loading = false);
    }
  }

  /// Another supplier replaces the lines; typed quantities would be lost, so the user is asked first.
  Future<bool> _changeSupplier(int? id, String? name) async {
    final typed = _lines.any((l) => l.qty.text.trim().isNotEmpty || l.lot.text.trim().isNotEmpty);
    if (typed && !await confirmDiscard(context)) {
      // The lookup already shows the new supplier; a new key puts the old one back.
      if (mounted) setState(() => _supplierEpoch++);
      return false;
    }
    if (!mounted) return false;
    setState(() {
      _supplierId = id;
      _supplierName = name;
    });
    if (id != null) {
      unawaited(_loadOrders());
    } else {
      setState(() => _lines = []);
    }
    return true;
  }

  num get _calculated => _lines.fold<num>(0, (a, l) => a + l.total());

  Future<void> _save() async {
    final date = parseDate(_date.text);
    final chosen = _lines.where((l) => (l.quantity ?? 0) > 0).toList();
    final typedTotal = _invoiceTotal.text.trim();
    final total = typedTotal.isEmpty ? null : parseDecimal(typedTotal);
    final divergent = total != null && (total - _calculated).abs() > 0.01;
    final badQty = _lines.where((l) => l.qty.text.trim().isNotEmpty && l.quantity == null).firstOrNull;
    final badPrice = chosen.where((l) => parseDecimal(l.price.text.trim()) == null).firstOrNull;
    final error = _supplierId == null
        ? 'Informe o fornecedor'
        : _invoice.text.trim().isEmpty
        ? 'Informe o número da NF'
        : date == null
        ? 'Data da NF inválida (dd/mm/aaaa)'
        : typedTotal.isNotEmpty && total == null
        ? 'Total da NF inválido'
        : chosen.isEmpty
        ? 'Informe a quantidade recebida em ao menos um item'
        : badQty != null
        ? 'Quantidade inválida em ${badQty.label}'
        : badPrice != null
        ? 'Preço inválido em ${badPrice.label}'
        : divergent && _justification.text.trim().isEmpty
        ? 'O total da NF difere do calculado: informe a justificativa da divergência'
        : null;
    if (error != null) return setState(() => _message = error);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await api.post('/api/goods-receipts', {
        'supplierId': _supplierId,
        'invoiceNumber': _invoice.text.trim(),
        'invoiceSeries': _series.text.trim().isEmpty ? null : _series.text.trim(),
        'invoiceDate': date,
        'invoiceTotal': total,
        'divergenceJustification': _justification.text.trim().isEmpty ? null : _justification.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'lines': [
          for (final l in chosen)
            {
              'purchaseOrderLineId': l.line['id'],
              'quantity': l.quantity,
              'unitPrice': parseDecimal(l.price.text.trim()),
              'lotCode': l.lot.text.trim().isEmpty ? null : l.lot.text.trim(),
            },
        ],
      }) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recebimento nº ${r['number']} registrado')));
      // The receipt takes this form's place: Back does not return to a filled-in form.
      await replaceWithReceipt(context, widget.session, r['id'] as int);
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {double width = 200, Key? key, String? hint, bool numeric = false}) => SizedBox(
    width: MediaQuery.sizeOf(context).width >= 700 ? width : double.infinity,
    child: TextField(
      key: key,
      controller: c,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final typed = parseDecimal(_invoiceTotal.text.trim());
    final diff = typed == null ? 0 : typed - _calculated;
    final divergent = typed != null && diff.abs() > 0.01;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Receber nota fiscal'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('receive-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Registrar'),
            ),
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
                width: wide ? 320 : double.infinity,
                child: LookupField(
                  key: ValueKey('receive-supplier-$_supplierEpoch'),
                  api: api,
                  spec: supplierLookup,
                  label: 'Fornecedor *',
                  value: _supplierId,
                  initialDisplay: _supplierName,
                  enabled: widget.supplierId == null,
                  onChanged: (id, entity) {
                    if (id == _supplierId) return;
                    unawaited(_changeSupplier(id, entity == null ? null : '${entity['name']}'));
                  },
                ),
              ),
              _field(_invoice, 'NF *', width: 140, key: const ValueKey('receive-invoice')),
              _field(_series, 'Série', width: 80),
              _field(_date, 'Data NF *', width: 140, hint: 'dd/mm/aaaa'),
              _field(_invoiceTotal, 'Total da NF', width: 160, numeric: true, key: const ValueKey('receive-total')),
              if (divergent) _field(_justification, 'Justificativa da divergência *', width: 360),
              _field(_notes, 'Observações', width: 360),
            ],
          ),
          const SizedBox(height: 16),
          Section(
            title: 'Itens em aberto',
            actions: [
              TextButton(
                onPressed: _lines.isEmpty
                    ? null
                    : () => setState(() {
                        for (final l in _lines) {
                          l.qty.text = fmt(l.line['openQuantity']);
                        }
                      }),
                child: const Text('Receber tudo'),
              ),
            ],
            child: _loading
                ? const LinearProgressIndicator()
                : _lines.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_supplierId == null ? 'Escolha o fornecedor' : 'Nenhum pedido em aberto para este fornecedor'),
                  )
                : Column(children: [for (final l in _lines) _lineRow(l, wide)]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Total calculado: ${fmtMoney(_calculated)}${typed == null ? '' : ' · Diferença: ${fmtMoney(diff)}'}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: divergent ? Theme.of(context).colorScheme.error : null),
            ),
          ),
          if (_message != null) Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    ));
  }

  Widget _lineRow(_OpenLine l, bool wide) {
    final ln = l.line;
    final late = isLate(ln['dueDate']);
    // When the form was opened from an order, the lines of other orders say so.
    final other = widget.purchaseOrderId != null && l.order['id'] != widget.purchaseOrderId;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pedido ${l.order['number']}/${ln['lineNumber']}${other ? ' (outro pedido)' : ''} · ${ln['materialCode'] ?? ''} ${ln['description']}', overflow: TextOverflow.ellipsis),
        Text(
          'Em aberto ${fmt(ln['openQuantity'])} ${ln['unit']} · entrega ${fmtDay(ln['dueDate'])}${late ? ' (atrasado)' : ''}',
          style: TextStyle(color: late ? Theme.of(context).colorScheme.error : null),
        ),
      ],
    );
    final inputs = [
      SizedBox(
        width: 120,
        child: TextField(
          key: ValueKey('receive-qty-${ln['id']}'),
          controller: l.qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'Qtd. (${ln['unit']})', border: const OutlineInputBorder(), isDense: true),
        ),
      ),
      SizedBox(
        width: 120,
        child: TextField(
          controller: l.price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Preço', border: OutlineInputBorder(), isDense: true),
        ),
      ),
      SizedBox(
        width: 120,
        child: TextField(
          controller: l.lot,
          decoration: const InputDecoration(labelText: 'Lote', border: OutlineInputBorder(), isDense: true),
        ),
      ),
      SizedBox(width: 110, child: Text(fmtMoney(l.total()), textAlign: TextAlign.right)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: wide
          ? Row(
              children: [
                Expanded(child: info),
                for (final w in inputs) Padding(padding: const EdgeInsets.only(left: 8), child: w),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: inputs),
              ],
            ),
    );
  }
}
