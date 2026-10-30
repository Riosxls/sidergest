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

const materialLookup = LookupSpec('/api/materials');
const productLookup = LookupSpec('/api/products');
const locationLookup = LookupSpec('/api/stock-locations');
const supplierLookup = LookupSpec('/api/suppliers');

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.session});

  final Session session;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _list = GlobalKey<RecordListState>();
  String? _type;

  Future<void> _new() async {
    final doc = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => StockPostScreen(session: widget.session)));
    _list.currentState?.reload();
    if (doc != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentScreen(session: widget.session, id: doc['id'] as int),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.session.api;
    return RecordList(
      key: _list,
      api: api,
      path: '/api/stock/documents',
      query: {'type': _type},
      searchParam: 'reference',
      searchHint: 'Referência exata',
      filters: [ChoiceFilter(label: 'Tipo', value: _type, choices: movementTypes, onChanged: (v) => setState(() => _type = v))],
      fab: widget.session.canStock
          ? FloatingActionButton.extended(heroTag: 'new-doc', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo lançamento'))
          : null,
      enrich: (items) => NameCache.attachSupplier(api, items),
      columns: [
        col('Nº', 'id'),
        dateCol('Data', 'date'),
        labelCol('Tipo', 'type', movementTypes),
        col('Referência', 'reference'),
        col('Fornecedor', 'supplierName'),
        col('Linhas', 'lines', numeric: true),
        col('Usuário', 'createdBy'),
        ColumnSpec('Situação', (e) => e['reversed'] == true ? 'Estornado' : (e['reversalOfId'] != null ? 'Estorno do nº ${e['reversalOfId']}' : '')),
      ],
      rowColor: (ctx, e) => e['reversed'] == true ? Theme.of(ctx).colorScheme.surfaceContainerHighest : null,
      onTap: (e) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentScreen(session: widget.session, id: e['id'] as int),
        ),
      ),
    );
  }
}

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late Future<Map<String, dynamic>> _future = _fetch();

  Future<Map<String, dynamic>> _fetch() async {
    final d = await widget.session.api.get('/api/stock/documents/${widget.id}') as Map<String, dynamic>;
    await NameCache.attachSupplier(widget.session.api, [d]);
    return d;
  }

  Future<void> _reverse() async {
    final notes = await promptText(context, title: 'Estornar documento nº ${widget.id}', label: 'Motivo', confirmLabel: 'Estornar');
    if (notes == null || !mounted) return;
    final r = await runAction(context, () => widget.session.api.post('/api/stock/documents/${widget.id}/reverse', {'notes': notes}));
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Estorno nº ${r['id']} lançado')));
    setState(() {
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        final canReverse = d != null && widget.session.canStock && d['reversed'] != true && d['type'] != 'Reversal';
        return Scaffold(
          appBar: AppBar(
            title: Text(d == null ? 'Documento nº ${widget.id}' : 'Nº ${d['id']} · ${movementTypes[d['type']] ?? d['type']}'),
            actions: [if (canReverse) TextButton.icon(onPressed: _reverse, icon: const Icon(Icons.undo), label: const Text('Estornar'))],
          ),
          body: snap.hasError
              ? Center(child: Text(friendlyError(snap.error!)))
              : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Section(
                      title: 'Documento',
                      child: InfoGrid([
                        ('Data', fmtDay(d['date'])),
                        ('Referência', fmt(d['reference'])),
                        ('Fornecedor', fmt(d['supplierName'])),
                        ('Lançado por', '${d['createdBy']} · ${fmtDate(d['createdAt'])}'),
                        ('Situação', d['reversed'] == true ? 'Estornado' : (d['reversalOfId'] != null ? 'Estorno do nº ${d['reversalOfId']}' : 'Ativo')),
                        ('Observações', fmt(d['notes'])),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Section(
                      title: 'Movimentos',
                      child: SimpleTable(
                        columns: [
                          col('Item', 'itemCode'),
                          labelCol('Tipo', 'type', movementTypes),
                          col('Local', 'locationCode'),
                          col('Lote', 'lotCode'),
                          col('Quantidade', 'quantity', numeric: true),
                          ColumnSpec('Custo unit.', (e) => fmtNum(e['unitCost'], 4), numeric: true),
                          col('ICMS %', 'icmsRate', numeric: true),
                          col('Reserva', 'reservationId'),
                        ],
                        rows: (d['movements'] as List).cast<Map<String, dynamic>>(),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

const _valued = {'OpeningBalance', 'Receipt', 'ThirdPartyReturn'};
const _outbound = {'Issue', 'IndirectIssue', 'Shipment', 'ReturnToSupplier', 'ThirdPartySend', 'AdjustmentOut'};
const _paired = {'Transfer', 'ThirdPartySend', 'ThirdPartyReturn'};
const _withSupplier = {'Receipt', 'ReturnToSupplier', 'ThirdPartySend', 'ThirdPartyReturn', 'OpeningBalance'};

List<FieldSpec> stockLineFields(String type) => [
  const FieldSpec('materialId', 'Material', type: FieldType.lookup, lookup: materialLookup, hint: 'Material ou produto, não ambos'),
  const FieldSpec('productId', 'Produto', type: FieldType.lookup, lookup: productLookup),
  if (_paired.contains(type))
    FieldSpec('fromLocationId', type == 'ThirdPartyReturn' ? 'Local de terceiros (origem)' : 'Local de origem', type: FieldType.lookup, lookup: locationLookup),
  FieldSpec(
    'locationId',
    type == 'ThirdPartySend' ? 'Local de terceiros (destino)' : (_paired.contains(type) ? 'Local de destino' : 'Local'),
    type: FieldType.lookup,
    lookup: locationLookup,
    required: true,
  ),
  FieldSpec('quantity', type == 'InventoryCount' ? 'Quantidade contada' : 'Quantidade', type: FieldType.decimal, required: true),
  if (_valued.contains(type)) ...[
    const FieldSpec('lotCode', 'Lote', hint: 'Vazio = número sequencial'),
    const FieldSpec('heatNumber', 'Corrida'),
    FieldSpec('unitCost', type == 'ThirdPartyReturn' ? 'Preço do serviço por kg' : 'Custo unitário', type: FieldType.decimal),
    const FieldSpec('icmsRate', 'ICMS (%)', type: FieldType.decimal),
  ],
  if (!_valued.contains(type) || type == 'ThirdPartyReturn')
    FieldSpec(
      'lotId',
      type == 'ThirdPartyReturn' ? 'Lote em terceiros' : 'Lote',
      type: FieldType.lookup,
      lookup: const LookupSpec('/api/stock/lots'),
      hint: _outbound.contains(type) || type == 'ThirdPartyReturn' ? 'Vazio = FIFO dos lotes liberados' : null,
    ),
  if (_outbound.contains(type))
    const FieldSpec(
      'reservationId',
      'Reserva consumida',
      type: FieldType.lookup,
      lookup: LookupSpec('/api/stock/reservations', query: {'status': 'Open'}, fetchById: false),
    ),
  if (type == 'ThirdPartyReturn') ...[
    const FieldSpec('sourceMaterialId', 'Material enviado (origem)', type: FieldType.lookup, lookup: materialLookup, hint: 'Vazio = mesmo material'),
    const FieldSpec('sourceQuantity', 'Quantidade baixada em terceiros', type: FieldType.decimal, hint: 'Vazio = quantidade retornada'),
  ],
];

class StockPostScreen extends StatefulWidget {
  const StockPostScreen({super.key, required this.session, this.type = 'Issue'});

  final Session session;
  final String type;

  @override
  State<StockPostScreen> createState() => _StockPostScreenState();
}

class _StockPostScreenState extends State<StockPostScreen> {
  late String _type = widget.type;
  final _date = TextEditingController(text: fmtDay(isoDate(DateTime.now())));
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  int? _supplierId;
  List<Map<String, dynamic>> _lines = [];
  String? _message;
  bool _busy = false;
  late final String _initial;

  String _signature() => jsonEncode([_type, _date.text, _reference.text, _notes.text, _supplierId, _lines]);

  ApiClient get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _initial = _signature();
  }

  @override
  void dispose() {
    _date.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final date = parseDate(_date.text);
    if (date == null) return setState(() => _message = 'Data inválida (dd/mm/aaaa)');
    if (_lines.isEmpty) return setState(() => _message = 'Inclua ao menos uma linha');
    final keys = stockLineFields(_type).map((f) => f.key).toSet();
    final body = {
      'type': _type,
      'date': date,
      'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      'supplierId': _withSupplier.contains(_type) ? _supplierId : null,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'lines': [for (final l in _lines) Map.fromEntries(stripLocal(l).entries.where((e) => keys.contains(e.key)))],
    };
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final doc = await api.post('/api/stock/documents', body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Documento nº ${doc['id']} lançado')));
      Navigator.pop(context, doc);
    } on ApiException catch (e) {
      setState(() => _message = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(parseDate(_date.text) ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date.text = fmtDay(isoDate(d)));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final w = wide ? 260.0 : double.infinity;
    return DiscardGuard(
      isDirty: () => _signature() != _initial,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Novo lançamento de estoque'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('post-stock'),
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: const Text('Lançar'),
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
                width: w,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('post-type'),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo *', border: OutlineInputBorder(), isDense: true),
                  items: [for (final t in postableTypes) DropdownMenuItem(value: t, child: Text(movementTypes[t]!))],
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
              SizedBox(
                width: wide ? 180 : w,
                child: TextField(
                  controller: _date,
                  decoration: InputDecoration(
                    labelText: 'Data *',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(tooltip: 'Escolher data', icon: const Icon(Icons.calendar_today, size: 18), onPressed: _pickDate),
                  ),
                ),
              ),
              SizedBox(
                width: w,
                child: TextField(
                  key: const ValueKey('post-reference'),
                  controller: _reference,
                  decoration: const InputDecoration(labelText: 'Referência (OP, NF, pedido…)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              if (_withSupplier.contains(_type))
                SizedBox(
                  width: w,
                  child: LookupField(
                    api: api,
                    spec: supplierLookup,
                    label: 'Fornecedor',
                    value: _supplierId,
                    onChanged: (id, _) => setState(() => _supplierId = id),
                  ),
                ),
              SizedBox(
                width: wide ? 540 : w,
                child: TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinesEditor(
            api: api,
            title: 'Linhas',
            fields: stockLineFields(_type),
            lines: _lines,
            onChanged: (l) => setState(() => _lines = l),
            columns: [
              ColumnSpec('Item', (e) => e['materialId'] != null ? lbl(e, 'materialId') : lbl(e, 'productId')),
              if (_paired.contains(_type)) ColumnSpec('Origem', (e) => lbl(e, 'fromLocationId')),
              ColumnSpec('Local', (e) => lbl(e, 'locationId')),
              ColumnSpec('Lote', (e) => e['lotCode'] as String? ?? lbl(e, 'lotId')),
              col('Quantidade', 'quantity', numeric: true),
              if (_valued.contains(_type)) col('Custo', 'unitCost', numeric: true),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    ));
  }
}
