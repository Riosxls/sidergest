import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/discard_guard.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';
import 'orders.dart';
import 'stock_documents.dart';

class ReceiptsView extends StatefulWidget {
  const ReceiptsView({super.key, required this.session, this.query = const {}, this.allowNew = false});

  final Session session;
  final Map<String, dynamic> query;
  final bool allowNew;

  @override
  State<ReceiptsView> createState() => _ReceiptsViewState();
}

class _ReceiptsViewState extends State<ReceiptsView> {
  final _list = GlobalKey<RecordListState>();

  Future<void> _new() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiveScreen(session: widget.session)));
    _list.currentState?.reload();
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
    onTap: (e) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(session: widget.session, id: e['id'] as int),
      ),
    ),
  );
}

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Recebimento nº $id')),
    body: FutureView<dynamic>(
      future: session.api.get('/api/goods-receipts/$id'),
      builder: (context, r) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Section(
            title: 'NF ${r['invoiceNumber']}${(r['invoiceSeries'] as String).isEmpty ? '' : '-${r['invoiceSeries']}'} · ${r['supplierName']}',
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
    ),
  );
}

class _OpenLine {
  _OpenLine(this.order, this.line) : price = TextEditingController(text: fmt(line['unitPrice']));

  final Map<String, dynamic> order;
  final Map<String, dynamic> line;
  final qty = TextEditingController();
  final TextEditingController price;
  final lot = TextEditingController();

  num? get quantity => qty.text.trim().isEmpty ? null : parseDecimal(qty.text.trim());

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

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.session, this.supplierId, this.supplierName});

  final Session session;
  final int? supplierId;
  final String? supplierName;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late int? _supplierId = widget.supplierId;
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
    setState(() {
      _loading = true;
      _lines = [];
    });
    try {
      final orders = await api.listAll('/api/purchase-orders', query: {'supplierId': _supplierId, 'open': true});
      final details = await Future.wait(orders.map((o) => api.get('/api/purchase-orders/${o['id']}')));
      final lines = <_OpenLine>[
        for (final d in details.cast<Map<String, dynamic>>())
          for (final l in (d['lines'] as List).cast<Map<String, dynamic>>())
            if (l['closed'] != true && (l['openQuantity'] as num) > 0) _OpenLine(d, l),
      ];
      lines.sort((a, b) => '${a.line['dueDate']}'.compareTo('${b.line['dueDate']}'));
      if (mounted) setState(() => _lines = lines);
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num get _calculated => _lines.fold<num>(0, (a, l) => a + l.total());

  Future<void> _save() async {
    final date = parseDate(_date.text);
    final chosen = _lines.where((l) => (l.quantity ?? 0) > 0).toList();
    final total = _invoiceTotal.text.trim().isEmpty ? null : parseDecimal(_invoiceTotal.text.trim());
    final error = _supplierId == null
        ? 'Informe o fornecedor'
        : _invoice.text.trim().isEmpty
        ? 'Informe o número da NF'
        : date == null
        ? 'Data da NF inválida (dd/mm/aaaa)'
        : chosen.isEmpty
        ? 'Informe a quantidade recebida em ao menos um item'
        : _lines.any((l) => l.qty.text.trim().isNotEmpty && l.quantity == null)
        ? 'Quantidade inválida'
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(session: widget.session, id: r['id'] as int),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
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
                  api: api,
                  spec: supplierLookup,
                  label: 'Fornecedor *',
                  value: _supplierId,
                  initialDisplay: widget.supplierName,
                  enabled: widget.supplierId == null,
                  onChanged: (id, _) {
                    setState(() => _supplierId = id);
                    if (id != null) _loadOrders();
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
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pedido ${l.order['number']}/${ln['lineNumber']} · ${ln['materialCode'] ?? ''} ${ln['description']}', overflow: TextOverflow.ellipsis),
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
