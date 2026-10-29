import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart' show showError;
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';

const _supplierLookup = LookupSpec('/api/suppliers');
const _lotLookup = LookupSpec('/api/steel/lots');

List<FieldSpec> _lotFields() => [
  const FieldSpec('lotCode', 'Lote / bobina', required: true),
  const FieldSpec('supplierId', 'Fornecedor (usina)', type: FieldType.lookup, required: true, lookup: _supplierLookup),
  FieldSpec('receivedDate', 'Data de recebimento', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
  const FieldSpec('purchaseInvoice', 'NF de compra'),
  const FieldSpec('specification', 'Especificação', hint: 'Ex.: DC01, SAE 1010'),
  const FieldSpec('thickness', 'Espessura (mm)', type: FieldType.decimal),
  const FieldSpec('width', 'Largura (mm)', type: FieldType.decimal),
  const FieldSpec('weightKg', 'Peso (kg)', type: FieldType.decimal, required: true),
  const FieldSpec('pricePerKg', 'Preço (R\$/kg)', type: FieldType.decimal, required: true),
  const FieldSpec('notes', 'Observações'),
];

List<FieldSpec> _jobFields() => [
  const FieldSpec('lotId', 'Lote / bobina', type: FieldType.lookup, required: true, lookup: _lotLookup),
  const FieldSpec('processorId', 'Beneficiador (slitter)', type: FieldType.lookup, required: true, lookup: _supplierLookup, hint: 'Ex.: Açoservice'),
  FieldSpec('shipmentDate', 'Data da remessa', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
  const FieldSpec('shipmentInvoice', 'NF de remessa'),
  const FieldSpec('sentKg', 'Peso enviado (kg)', type: FieldType.decimal, required: true),
  const FieldSpec('returnInvoice', 'NF de retorno'),
  const FieldSpec('returnDate', 'Data do retorno', type: FieldType.date),
  const FieldSpec('finishedKg', 'Peso acabado (kg)', type: FieldType.decimal),
  const FieldSpec('scrapKg', 'Refilo (kg)', type: FieldType.decimal),
  const FieldSpec('serviceCost', 'Custo do serviço (R\$)', type: FieldType.decimal),
  const FieldSpec('notes', 'Observações'),
];

const _returnFields = [
  FieldSpec('returnInvoice', 'NF de retorno', required: true),
  FieldSpec('returnDate', 'Data do retorno', type: FieldType.date, required: true),
  FieldSpec('finishedKg', 'Peso acabado (kg)', type: FieldType.decimal, required: true),
  FieldSpec('scrapKg', 'Refilo (kg)', type: FieldType.decimal),
  FieldSpec('serviceCost', 'Custo do serviço (R\$)', type: FieldType.decimal),
];

List<FieldSpec> _usageFields() => [
  const FieldSpec('lotId', 'Lote / bobina', type: FieldType.lookup, required: true, lookup: _lotLookup),
  FieldSpec('date', 'Data', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
  const FieldSpec('kg', 'Peso usado (kg)', type: FieldType.decimal, required: true),
  const FieldSpec('laborCost', 'Mão de obra (R\$)', type: FieldType.decimal, required: true, defaultValue: 0),
  const FieldSpec('reference', 'Referência', hint: 'OF, pedido…'),
  const FieldSpec('notes', 'Observações'),
];

Future<void> openSteelLot(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => SteelLotScreen(session: session, id: id),
  ),
);

Map<String, dynamic> _lotPreset(Map<String, dynamic> lot) => {
  'lotId': lot['id'],
  '_labels': {'lotId': '${lot['lotCode']}'},
};

Map<String, dynamic> _jobInitial(Map<String, dynamic> j) => {
  for (final k in [
    'lotId',
    'processorId',
    'shipmentDate',
    'shipmentInvoice',
    'sentKg',
    'returnInvoice',
    'returnDate',
    'finishedKg',
    'scrapKg',
    'serviceCost',
    'notes',
  ])
    k: j[k],
  '_labels': {'lotId': '${j['lotCode']}', 'processorId': '${j['processorName']}'},
};

class SteelScreen extends StatefulWidget {
  const SteelScreen({super.key, required this.session});

  final Session session;

  @override
  State<SteelScreen> createState() => _SteelScreenState();
}

class _SteelScreenState extends State<SteelScreen> {
  final _lots = GlobalKey<RecordListState>();
  final _jobs = GlobalKey<RecordListState>();
  final _usages = GlobalKey<RecordListState>();

  Session get s => widget.session;
  ApiClient get api => s.api;

  Future<void> _create(GlobalKey<RecordListState> list, String title, String path, List<FieldSpec> fields, {bool openLot = false}) async {
    final r = await submitForm(context, api: api, title: title, fields: fields, submit: (b) => api.post(path, b));
    _lots.currentState?.reload();
    _jobs.currentState?.reload();
    _usages.currentState?.reload();
    if (openLot && r != null && r['id'] is int && mounted) {
      await openSteelLot(context, s, r['id'] as int);
      _lots.currentState?.reload();
    }
  }

  Future<void> _editJob(Map<String, dynamic> e) async {
    if (!s.canSteel) return openSteelLot(context, s, e['lotId'] as int);
    await submitForm(
      context,
      api: api,
      title: 'Remessa ${fmt(e['shipmentInvoice'])}',
      fields: _jobFields(),
      initial: _jobInitial(e),
      submit: (b) => api.put('/api/steel/slitter/${e['id']}', b),
    );
  }

  Widget _fab(String key, String label, VoidCallback onPressed) =>
      FloatingActionButton.extended(heroTag: key, onPressed: onPressed, icon: const Icon(Icons.add), label: Text(label));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: cs.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(key: ValueKey('steel-tab-lots'), text: 'Bobinas e lotes'),
                Tab(key: ValueKey('steel-tab-slitter'), text: 'Slitter (beneficiamento)'),
                Tab(key: ValueKey('steel-tab-usage'), text: 'Uso interno'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                RecordList(
                  key: _lots,
                  api: api,
                  path: '/api/steel/lots',
                  searchHint: 'Lote, NF de compra, fornecedor ou especificação',
                  fab: s.canSteel
                      ? _fab('new-steel-lot', 'Nova bobina', () => _create(_lots, 'Nova bobina', '/api/steel/lots', _lotFields(), openLot: true))
                      : null,
                  columns: [
                    col('Lote', 'lotCode'),
                    col('Fornecedor', 'supplierName'),
                    col('NF compra', 'purchaseInvoice'),
                    dateCol('Recebida', 'receivedDate'),
                    col('Espec.', 'specification'),
                    col('Peso (kg)', 'weightKg', numeric: true),
                    ColumnSpec('R\$/kg', (e) => fmtNum(e['pricePerKg'], 4), numeric: true),
                    col('Saldo (kg)', 'balanceKg', numeric: true),
                    moneyCol('Saldo R\$', 'balanceValue'),
                    ColumnSpec('Slitter', (e) => (e['pendingJobs'] as num? ?? 0) > 0 ? '${e['pendingJobs']} pendente(s)' : ''),
                  ],
                  rowColor: (ctx, e) => (e['balanceKg'] as num? ?? 0) < 0 ? toneColors(ctx, Tone.danger).$1 : null,
                  onTap: (e) async {
                    await openSteelLot(context, s, e['id'] as int);
                    _lots.currentState?.reload();
                  },
                ),
                RecordList(
                  key: _jobs,
                  api: api,
                  path: '/api/steel/slitter',
                  searchHint: 'Lote, NF de remessa/retorno ou beneficiador',
                  fab: s.canSteel
                      ? _fab('new-slitter-job', 'Nova remessa', () => _create(_jobs, 'Remessa ao slitter', '/api/steel/slitter', _jobFields()))
                      : null,
                  columns: [
                    col('Lote', 'lotCode'),
                    col('Beneficiador', 'processorName'),
                    col('NF remessa', 'shipmentInvoice'),
                    dateCol('Remessa', 'shipmentDate'),
                    col('Enviado (kg)', 'sentKg', numeric: true),
                    col('NF retorno', 'returnInvoice'),
                    col('Acabado (kg)', 'finishedKg', numeric: true),
                    col('Refilo (kg)', 'scrapKg', numeric: true),
                    ColumnSpec('Perda %', (e) => e['lossPercent'] == null ? '' : fmtNum(e['lossPercent'], 2), numeric: true),
                    ColumnSpec('Situação', (e) => e['returned'] == true ? 'Retornou' : 'No slitter'),
                  ],
                  rowColor: (ctx, e) => e['returned'] == true ? null : toneColors(ctx, Tone.warning).$1,
                  onTap: _editJob,
                ),
                RecordList(
                  key: _usages,
                  api: api,
                  path: '/api/steel/usages',
                  searchHint: 'Lote ou referência',
                  fab: s.canSteel
                      ? _fab('new-steel-usage', 'Novo consumo', () => _create(_usages, 'Uso interno de aço', '/api/steel/usages', _usageFields()))
                      : null,
                  columns: [
                    col('Lote', 'lotCode'),
                    dateCol('Data', 'date'),
                    col('Peso (kg)', 'kg', numeric: true),
                    moneyCol('Mão de obra', 'laborCost'),
                    col('Referência', 'reference'),
                    col('Observações', 'notes'),
                  ],
                  onTap: (e) async {
                    if (!s.canSteel) return;
                    await submitForm(
                      context,
                      api: api,
                      title: 'Uso interno · ${e['lotCode']}',
                      fields: _usageFields(),
                      initial: {
                        for (final k in ['lotId', 'date', 'kg', 'laborCost', 'reference', 'notes']) k: e[k],
                        '_labels': {'lotId': '${e['lotCode']}'},
                      },
                      submit: (b) => api.put('/api/steel/usages/${e['id']}', b),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SteelLotScreen extends StatefulWidget {
  const SteelLotScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<SteelLotScreen> createState() => _SteelLotScreenState();
}

class _SteelLotScreenState extends State<SteelLotScreen> {
  Map<String, dynamic>? _lot;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _usages = [];
  String? _error;

  Session get s => widget.session;
  ApiClient get api => s.api;
  String get base => '/api/steel/lots/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.get(base), api.get('$base/slitter'), api.get('$base/usages')]);
      if (!mounted) return;
      setState(() {
        _lot = r[0] as Map<String, dynamic>;
        _jobs = (r[1] as List).cast<Map<String, dynamic>>();
        _usages = (r[2] as List).cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _editLot() async {
    final l = _lot!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Editar ${l['lotCode']}',
      fields: _lotFields(),
      initial: {
        for (final k in ['lotCode', 'supplierId', 'receivedDate', 'purchaseInvoice', 'specification', 'thickness', 'width', 'weightKg', 'pricePerKg', 'notes'])
          k: l[k],
        '_labels': {'supplierId': '${l['supplierName']}'},
      },
      submit: (b) => api.put(base, b),
    );
    if (r != null) _load();
  }

  Future<void> _deleteLot() async {
    final ok = await confirmStep(
      context,
      title: 'Excluir ${_lot!['lotCode']}?',
      message: 'Só lotes sem remessas e sem uso interno podem ser excluídos.',
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await api.delete(base);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e is ApiException ? describeError(e) : e);
    }
  }

  Future<void> _newJob() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Remessa ao slitter',
      fields: _jobFields(),
      initial: {..._lotPreset(_lot!), 'shipmentDate': isoDate(DateTime.now())},
      submit: (b) => api.post('/api/steel/slitter', b),
    );
    if (r != null) _load();
  }

  Future<void> _editJob(Map<String, dynamic> j) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Remessa ${fmt(j['shipmentInvoice'])}',
      fields: _jobFields(),
      initial: _jobInitial(j),
      submit: (b) => api.put('/api/steel/slitter/${j['id']}', b),
    );
    if (r != null) _load();
  }

  Future<void> _returnJob(Map<String, dynamic> j) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Retorno do slitter',
      fields: _returnFields,
      initial: {
        for (final k in ['returnInvoice', 'returnDate', 'finishedKg', 'scrapKg', 'serviceCost']) k: j[k],
        'returnDate': isoDate(DateTime.now()),
      },
      submit: (b) => api.put('/api/steel/slitter/${j['id']}', {..._jobInitial(j)..remove('_labels'), ...b}),
    );
    if (r != null) _load();
  }

  Future<void> _deleteChild(String path, String what) async {
    if (!await confirmStep(context, title: 'Remover $what?', message: 'O saldo do lote é recalculado.', confirmLabel: 'Remover', danger: true)) return;
    if (!mounted) return;
    await runAction(context, () => api.delete(path));
    _load();
  }

  Future<void> _newUsage() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Uso interno de aço',
      fields: _usageFields(),
      initial: {..._lotPreset(_lot!), 'date': isoDate(DateTime.now()), 'laborCost': 0},
      submit: (b) => api.post('/api/steel/usages', b),
    );
    if (r != null) _load();
  }

  Future<void> _editUsage(Map<String, dynamic> u) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Uso interno · ${u['lotCode']}',
      fields: _usageFields(),
      initial: {
        for (final k in ['lotId', 'date', 'kg', 'laborCost', 'reference', 'notes']) k: u[k],
        '_labels': {'lotId': '${u['lotCode']}'},
      },
      submit: (b) => api.put('/api/steel/usages/${u['id']}', b),
    );
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lot;
    return Scaffold(
      appBar: AppBar(
        title: Text(l == null ? 'Lote de aço' : '${l['lotCode']} · ${l['supplierName']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (l != null && s.canSteel)
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('lot-menu'),
              onSelected: (f) => f(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _editLot,
                  child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar lote')),
                ),
                PopupMenuItem(
                  value: _deleteLot,
                  child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir lote')),
                ),
              ],
            ),
        ],
      ),
      body: _error != null && l == null
          ? Center(child: Text(_error!))
          : l == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(l)),
    );
  }

  Widget _kpi(String label, String value, {String? caption, IconData? icon, Tone tone = Tone.info}) => SizedBox(
    width: 220,
    child: KpiTile(label: label, value: value, caption: caption, icon: icon, tone: tone),
  );

  Widget _body(Map<String, dynamic> l) {
    final returned = _jobs.where((j) => j['returned'] == true).toList();
    final sentReturned = returned.fold<num>(0, (a, j) => a + (j['sentKg'] as num));
    final finished = returned.fold<num>(0, (a, j) => a + ((j['finishedKg'] as num?) ?? 0));
    final loss = sentReturned == 0 ? null : (sentReturned - finished) / sentReturned * 100;
    final negative = (l['balanceKg'] as num) < 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(
              'Saldo (kg)',
              fmt(l['balanceKg']),
              caption: negative ? 'Consumo maior que o saldo' : null,
              icon: Icons.scale_outlined,
              tone: negative ? Tone.danger : Tone.success,
            ),
            _kpi('Saldo (R\$)', fmtMoney(l['balanceValue']), icon: Icons.payments_outlined),
            _kpi(
              'Comprado',
              '${fmt(l['weightKg'])} kg',
              caption: '${fmtNum(l['pricePerKg'], 4)} R\$/kg · ${fmtMoney(l['purchaseValue'])}',
              icon: Icons.shopping_cart_outlined,
            ),
            _kpi(
              'No slitter',
              '${fmt((l['sentKg'] as num) - (l['returnedKg'] as num))} kg',
              caption: '${l['pendingJobs']} remessa(s) pendente(s)',
              icon: Icons.content_cut,
              tone: (l['pendingJobs'] as num) > 0 ? Tone.warning : Tone.neutral,
            ),
            _kpi(
              'Retornado',
              '${fmt(l['returnedKg'])} kg',
              caption: 'Refilo ${fmt(l['scrapKg'])} kg${loss == null ? '' : ' · perda ${fmtNum(loss, 2)}%'}',
              icon: Icons.south_west,
              tone: Tone.progress,
            ),
            _kpi('Uso interno', '${fmt(l['usedKg'])} kg', caption: 'Mão de obra ${fmtMoney(l['laborCost'])}', icon: Icons.precision_manufacturing_outlined),
            _kpi(
              'Custo total',
              fmtMoney(l['totalCost']),
              caption: 'Compra + slitter ${fmtMoney(l['serviceCost'])} + mão de obra',
              icon: Icons.calculate_outlined,
            ),
          ],
        ),
        gap,
        Section(
          title: 'Dados do lote',
          child: InfoGrid([
            ('NF de compra', fmt(l['purchaseInvoice'])),
            ('Recebida em', fmtDay(l['receivedDate'])),
            ('Especificação', fmt(l['specification'])),
            ('Espessura (mm)', fmt(l['thickness'])),
            ('Largura (mm)', fmt(l['width'])),
            ('Observações', fmt(l['notes'])),
          ]),
        ),
        gap,
        Section(
          title: 'Slitter (${_jobs.length})',
          actions: [
            if (s.canSteel)
              FilledButton.tonalIcon(key: const ValueKey('lot-new-job'), onPressed: _newJob, icon: const Icon(Icons.add), label: const Text('Remessa')),
          ],
          child: SimpleTable(
            columns: [
              col('Beneficiador', 'processorName'),
              col('NF remessa', 'shipmentInvoice'),
              dateCol('Remessa', 'shipmentDate'),
              col('Enviado (kg)', 'sentKg', numeric: true),
              col('NF retorno', 'returnInvoice'),
              dateCol('Retorno', 'returnDate'),
              col('Acabado (kg)', 'finishedKg', numeric: true),
              col('Refilo (kg)', 'scrapKg', numeric: true),
              ColumnSpec('Perda %', (e) => e['lossPercent'] == null ? '' : fmtNum(e['lossPercent'], 2), numeric: true),
              moneyCol('Serviço', 'serviceCost'),
            ],
            rows: _jobs,
            actions: s.canSteel
                ? (j) => [
                    if (j['returned'] != true)
                      TextButton(key: ValueKey('job-return-${j['id']}'), onPressed: () => _returnJob(j), child: const Text('Registrar retorno')),
                    IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editJob(j)),
                    IconButton(
                      tooltip: 'Remover',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteChild('/api/steel/slitter/${j['id']}', 'remessa'),
                    ),
                  ]
                : null,
          ),
        ),
        gap,
        Section(
          title: 'Uso interno (${_usages.length})',
          actions: [
            if (s.canSteel)
              FilledButton.tonalIcon(key: const ValueKey('lot-new-usage'), onPressed: _newUsage, icon: const Icon(Icons.add), label: const Text('Consumo')),
          ],
          child: SimpleTable(
            columns: [
              dateCol('Data', 'date'),
              col('Peso (kg)', 'kg', numeric: true),
              moneyCol('Mão de obra', 'laborCost'),
              col('Referência', 'reference'),
              col('Observações', 'notes'),
            ],
            rows: _usages,
            actions: s.canSteel
                ? (u) => [
                    IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editUsage(u)),
                    IconButton(
                      tooltip: 'Remover',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteChild('/api/steel/usages/${u['id']}', 'consumo'),
                    ),
                  ]
                : null,
          ),
        ),
      ],
    );
  }
}
