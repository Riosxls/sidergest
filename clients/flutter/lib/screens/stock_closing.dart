import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';

int? parsePeriod(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(s.trim());
  if (m == null) return null;
  final month = int.parse(m[1]!);
  return month < 1 || month > 12 ? null : int.parse(m[2]!) * 100 + month;
}

int nextPeriod(int p) => p % 100 == 12 ? (p ~/ 100 + 1) * 100 + 1 : p + 1;

class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key, required this.session});

  final Session session;

  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  final _period = TextEditingController();
  List<Map<String, dynamic>> _closings = [];
  List<Map<String, dynamic>>? _rows;
  String _mode = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadClosings(setDefault: true);
  }

  @override
  void dispose() {
    _period.dispose();
    super.dispose();
  }

  int? get _last => _closings.isEmpty ? null : _closings.first['period'] as int;

  Future<void> _loadClosings({bool setDefault = false}) async {
    try {
      final l = (await widget.session.api.get('/api/stock/closings') as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() => _closings = l);
      if (setDefault) {
        final now = DateTime.now();
        final prev = now.month == 1 ? (now.year - 1) * 100 + 12 : now.year * 100 + now.month - 1;
        _period.text = fmtPeriod(_last == null ? prev : nextPeriod(_last!));
        await _preview();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _fetch(String mode, String path, Map<String, dynamic> query) async {
    final p = parsePeriod(_period.text);
    if (p == null) return setState(() => _error = 'Período inválido (mm/aaaa)');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = (await widget.session.api.get(path, {...query, 'period': p}) as List).cast<Map<String, dynamic>>();
      await NameCache.attach(widget.session.api, rows, 'materialId', '/api/materials', 'materialCode', (m) => '${m['code']}');
      if (mounted) {
        setState(() {
          _rows = rows;
          _mode = '$mode ${fmtPeriod(p)}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() => _fetch('Prévia', '/api/stock/average-costs/preview', {});

  Future<void> _view() => _fetch('Custos gravados', '/api/stock/average-costs', {});

  Future<void> _close() async {
    final p = parsePeriod(_period.text);
    if (p == null) return setState(() => _error = 'Período inválido (mm/aaaa)');
    if (!await confirm(context, 'Fechar ${fmtPeriod(p)}? O mês não aceitará novos lançamentos nem estornos.')) return;
    if (!mounted) return;
    final r = await runAction(context, () => widget.session.api.post('/api/stock/closings/$p', {}), success: 'Mês ${fmtPeriod(p)} fechado');
    if (r == null) return;
    await _loadClosings();
    await _view();
  }

  Future<void> _reopen() async {
    final p = _last!;
    if (!await confirm(context, 'Reabrir ${fmtPeriod(p)}? Os custos médios do mês serão descartados.')) return;
    if (!mounted) return;
    await runAction(context, () => widget.session.api.delete('/api/stock/closings/$p'), success: 'Mês ${fmtPeriod(p)} reaberto');
    _period.text = fmtPeriod(p);
    await _loadClosings();
    await _preview();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Fechamento mensal e custo médio',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  key: const ValueKey('closing-period'),
                  controller: _period,
                  decoration: const InputDecoration(labelText: 'Período', hintText: 'mm/aaaa', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              OutlinedButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.calculate_outlined), label: const Text('Prévia')),
              OutlinedButton.icon(onPressed: _busy ? null : _view, icon: const Icon(Icons.history), label: const Text('Consultar')),
              if (s.canStock) FilledButton.icon(onPressed: _busy ? null : _close, icon: const Icon(Icons.lock_outline), label: const Text('Fechar mês')),
              if (s.isAdmin && _last != null)
                TextButton.icon(onPressed: _busy ? null : _reopen, icon: const Icon(Icons.lock_open), label: Text('Reabrir ${fmtPeriod(_last)}')),
              Text(
                _last == null
                    ? 'Nenhum mês fechado'
                    : 'Último fechado: ${fmtPeriod(_last)} por ${_closings.first['closedBy']} em ${fmtDate(_closings.first['closedAt'])}',
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (rows != null) ...[
          const SizedBox(height: 12),
          Section(
            title: '$_mode (${rows.length})',
            child: SimpleTable(
              columns: [
                ColumnSpec('Espessura', (e) => e['thicknessMm'] == null ? '—' : '${fmt(e['thicknessMm'])} mm'),
                col('Material', 'materialCode'),
                col('Saldo inicial', 'openingQuantity', numeric: true),
                ColumnSpec('Médio anterior', (e) => fmtNum(e['openingAverage'], 4), numeric: true),
                col('Compras (qtd)', 'purchaseQuantity', numeric: true),
                moneyCol('Compras (valor)', 'purchaseValue'),
                col('Serviços (qtd)', 'serviceQuantity', numeric: true),
                moneyCol('Serviços (valor)', 'serviceValue'),
                ColumnSpec('Médio do mês', (e) => fmtNum(e['monthAverage'], 4), numeric: true),
                ColumnSpec('Médio', (e) => fmtNum(e['average'], 4), numeric: true),
                ColumnSpec('Médio bruto', (e) => fmtNum(e['averageGross'], 4), numeric: true),
                ColumnSpec('Importado', (e) => e['imported'] == true ? 'Sim' : ''),
              ],
              rows: rows,
            ),
          ),
        ],
        if (_closings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Section(
            title: 'Meses fechados',
            child: SimpleTable(
              columns: [ColumnSpec('Período', (e) => fmtPeriod(e['period'])), col('Fechado por', 'closedBy'), ColumnSpec('Em', (e) => fmtDate(e['closedAt']))],
              rows: _closings.take(24).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<dynamic>> _future = _fetch();

  static const stockFields = [
    FieldSpec('allowNegativeStock', 'Permitir saldo negativo', type: FieldType.boolean),
    FieldSpec('deductIcmsFromAverage', 'Deduzir ICMS do custo médio', type: FieldType.boolean),
    FieldSpec('cuttingServicePerKg', 'Serviço de corte (R\$/kg)', type: FieldType.decimal, required: true),
    FieldSpec('scrapResalePerKg', 'Revenda de sucata (R\$/kg)', type: FieldType.decimal, required: true),
    FieldSpec('scrapPercent', 'Sucata (%)', type: FieldType.decimal, required: true),
  ];

  static const purchasingFields = [
    FieldSpec('receivingTolerancePercent', 'Tolerância de recebimento (%)', type: FieldType.decimal, required: true),
    FieldSpec('allowEarlyReceipt', 'Aceitar entrega antecipada', type: FieldType.boolean),
    FieldSpec('earlyReceiptGraceDays', 'Antecipação aceita (dias)', type: FieldType.integer, required: true),
    FieldSpec('receivingLocationId', 'Local de recebimento', type: FieldType.lookup, lookup: LookupSpec('/api/stock-locations'), hint: 'Vazio = ALM'),
  ];

  Future<List<dynamic>> _fetch() async {
    final api = widget.session.api;
    final r = await Future.wait([api.get('/api/stock/settings'), api.get('/api/purchasing/settings')]);
    final p = r[1] as Map<String, dynamic>;
    if (p['receivingLocationId'] is int) p['receivingLocation'] = await NameCache.name(api, '/api/stock-locations', p['receivingLocationId'] as int);
    return r;
  }

  Future<void> _edit(String title, String path, List<FieldSpec> fields, Map<String, dynamic> current) async {
    final r = await showEntityForm(
      context,
      api: widget.session.api,
      title: title,
      fields: fields,
      initial: current,
      readOnly: !widget.session.isAdmin,
      onSubmit: (b) async => await widget.session.api.put(path, b) as Map<String, dynamic>?,
    );
    if (r == null) return;
    setState(() {
      _future = _fetch();
    });
  }

  Widget _card(String title, String path, List<FieldSpec> fields, Map<String, dynamic> v, List<(String, String)> info) => Section(
    title: title,
    actions: [
      IconButton(
        tooltip: widget.session.isAdmin ? 'Editar' : 'Ver',
        icon: Icon(widget.session.isAdmin ? Icons.edit_outlined : Icons.visibility_outlined),
        onPressed: () => _edit(title, path, fields, v),
      ),
    ],
    child: InfoGrid(info),
  );

  @override
  Widget build(BuildContext context) => FutureView<List<dynamic>>(
    future: _future,
    onRetry: () => setState(() {
      _future = _fetch();
    }),
    builder: (context, r) {
      final st = r[0] as Map<String, dynamic>;
      final pu = r[1] as Map<String, dynamic>;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('Estoque', '/api/stock/settings', stockFields, st, [
            ('Saldo negativo', st['allowNegativeStock'] == true ? 'Permitido' : 'Bloqueado'),
            ('ICMS no custo médio', st['deductIcmsFromAverage'] == true ? 'Deduzido' : 'Incluído'),
            ('Serviço de corte', '${fmtMoney(st['cuttingServicePerKg'])}/kg'),
            ('Revenda de sucata', '${fmtMoney(st['scrapResalePerKg'])}/kg'),
            ('Sucata', '${fmt(st['scrapPercent'])} %'),
          ]),
          const SizedBox(height: 12),
          _card('Compras e recebimento', '/api/purchasing/settings', purchasingFields, pu, [
            ('Tolerância de recebimento', '${fmt(pu['receivingTolerancePercent'])} %'),
            ('Entrega antecipada', pu['allowEarlyReceipt'] == true ? 'Aceita até ${pu['earlyReceiptGraceDays']} dias' : 'Não aceita'),
            ('Local de recebimento', fmt(pu['receivingLocation'] ?? 'ALM (padrão)')),
          ]),
        ],
      );
    },
  );
}
