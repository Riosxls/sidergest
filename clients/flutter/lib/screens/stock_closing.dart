import 'dart:async';

import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/page_column.dart';
import '../widgets/pipeline.dart' show confirmStep;
import '../widgets/record_list.dart';
import '../widgets/responsive.dart';

int? parsePeriod(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(s.trim());
  if (m == null) return null;
  final month = int.parse(m[1]!);
  return month < 1 || month > 12 ? null : int.parse(m[2]!) * 100 + month;
}

int nextPeriod(int p) => p % 100 == 12 ? (p ~/ 100 + 1) * 100 + 1 : p + 1;

/// Stock period closing screen.
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

  /// Period of the rows on screen, when they are a preview or the stored costs of that period.
  int? _shownPeriod;

  @override
  void initState() {
    super.initState();
    _loadClosings(setDefault: true);
  }

  /// Another tab (a posted document, a reversal) changed the movements: whatever was calculated here is old.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive && _rows != null && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_loadClosings());
        if (_mode.startsWith('Prévia')) unawaited(_preview());
      });
    }
    _wasActive = active;
  }

  bool _wasActive = true;

  @override
  void dispose() {
    _period.dispose();
    super.dispose();
  }

  /// The figures on screen are a preview of the period typed: closing is only offered on numbers the user has seen.
  bool get _previewed => _mode.startsWith('Prévia') && _shownPeriod != null && _shownPeriod == parsePeriod(_period.text);

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
      if (mounted) setState(() => _error = friendlyError(e));
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
          _shownPeriod = p;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tries again what failed: the list of closings (nothing loaded yet) or the preview.
  Future<void> _retry() async {
    setState(() => _error = null);
    if (_period.text.trim().isEmpty) return _loadClosings(setDefault: true);
    await _loadClosings();
    if (mounted && _error == null) await _preview();
  }

  Future<void> _preview() => _fetch('Prévia', '/api/stock/average-costs/preview', {});

  Future<void> _view() => _fetch('Custos gravados', '/api/stock/average-costs', {});

  Future<void> _close() async {
    final p = parsePeriod(_period.text);
    if (p == null) return setState(() => _error = 'Período inválido (mm/aaaa)');
    // Closing is only offered on figures the user has seen: a period typed after the last preview gets its own preview first.
    if (_shownPeriod != p || !_mode.startsWith('Prévia')) {
      await _preview();
      if (!mounted || _shownPeriod != p || _error != null) return;
    }
    final count = _rows?.length ?? 0;
    final ok = await confirmStep(
      context,
      title: 'Fechar ${fmtPeriod(p)}?',
      message: 'A prévia acima tem $count linhas de custo médio e passa a valer. O mês não aceitará novos lançamentos nem estornos.',
      confirmLabel: 'Fechar ${fmtPeriod(p)}',
      icon: Icons.lock_outline,
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => widget.session.api.post('/api/stock/closings/$p', {}), success: 'Mês ${fmtPeriod(p)} fechado');
    if (r == null) return;
    await _loadClosings();
    await _view();
  }

  /// Defines the Médio columns where the user looks for them, in a dialog that opens from the info icon of the table.
  Future<void> _explainColumns() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Colunas de custo médio'),
      content: SizedBox(
        width: dialogWidth(context, 460),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Médio do mês: custo médio das entradas do mês (compras e serviços, com a sucata).'),
            SizedBox(height: AppSpacing.sm),
            Text('Médio: média ponderada entre o saldo anterior e o mês, sem o ICMS quando a configuração manda deduzir.'),
            SizedBox(height: AppSpacing.sm),
            Text('Médio bruto: a mesma média com o ICMS incluído.'),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar'))],
    ),
  );

  Future<void> _reopen() async {
    final p = _last!;
    final ok = await confirmStep(
      context,
      title: 'Reabrir ${fmtPeriod(p)}?',
      message: 'Os custos médios do mês são descartados e o mês volta a aceitar lançamentos e estornos. Feche-o de novo depois de corrigir.',
      confirmLabel: 'Reabrir ${fmtPeriod(p)}',
      icon: Icons.lock_open,
      cancelLabel: 'Voltar',
      danger: true,
    );
    if (!ok || !mounted) return;
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
          title: 'Período',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Where the books stand comes first: the controls below act on the month after this one.
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    key: const ValueKey('closing-last'),
                    _last == null
                        ? 'Nenhum mês fechado'
                        : 'Último fechado: ${fmtPeriod(_last)} por ${_closings.first['closedBy']} em ${fmtDate(_closings.first['closedAt'])}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  // Next to the month it reopens, in the error colour: it throws the month's costs away.
                  if (s.isAdmin && _last != null)
                    TextButton.icon(
                      key: const ValueKey('closing-reopen'),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      onPressed: _busy ? null : _reopen,
                      icon: const Icon(Icons.lock_open),
                      label: Text('Reabrir ${fmtPeriod(_last)}'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      key: const ValueKey('closing-period'),
                      controller: _period,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Período', hintText: 'mm/aaaa', border: OutlineInputBorder(), isDense: true),
                      onSubmitted: (_) => _busy ? null : _preview(),
                    ),
                  ),
                  OutlinedButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.calculate_outlined), label: const Text('Prévia')),
                  OutlinedButton.icon(onPressed: _busy ? null : _view, icon: const Icon(Icons.history), label: const Text('Consultar')),
                  if (s.canStock)
                    FilledButton.icon(
                      key: const ValueKey('closing-close'),
                      onPressed: _busy || !_previewed ? null : _close,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Fechar mês'),
                    ),
                ],
              ),
              // A disabled button has to say why; a tooltip would not show on touch.
              if (s.canStock && !_previewed && !_busy)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Calcule a prévia deste período para poder fechar o mês.',
                    key: const ValueKey('closing-hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  TextButton(key: const ValueKey('closing-retry'), onPressed: _busy ? null : _retry, child: const Text('Tentar novamente')),
                ],
              ),
            ),
          ),
        if (rows != null) ...[
          const SizedBox(height: 12),
          Section(
            title: '$_mode (${rows.length})',
            actions: [
              IconButton(
                key: const ValueKey('closing-columns-info'),
                tooltip: 'O que são as colunas Médio',
                icon: const Icon(Icons.info_outline),
                onPressed: _explainColumns,
              ),
            ],
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
              hideWhenEmpty: const {'Serviços (qtd)', 'Serviços (valor)', 'Importado'},
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

/// Stock settings screen.
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

  static const productionFields = [
    FieldSpec('overrunTolerancePercent', 'Tolerância de excedente (%)', type: FieldType.decimal, required: true),
    FieldSpec('hoursPerDay', 'Horas por dia', type: FieldType.decimal, required: true),
    FieldSpec('workSaturdays', 'Trabalha aos sábados', type: FieldType.boolean),
    FieldSpec('issueLocationId', 'Local de requisição', type: FieldType.lookup, lookup: LookupSpec('/api/stock-locations'), hint: 'Vazio = ALM'),
    FieldSpec('receiptLocationId', 'Local de entrada de acabado', type: FieldType.lookup, lookup: LookupSpec('/api/stock-locations'), hint: 'Vazio = PA'),
  ];

  static const salesFields = [
    FieldSpec('maxDiscountPercent', 'Desconto máximo sem autorização (%)', type: FieldType.decimal, required: true),
    FieldSpec('defaultValidityDays', 'Validade padrão do orçamento (dias)', type: FieldType.integer, required: true),
    FieldSpec('minimumOrderValue', 'Faturamento mínimo (R\$)', type: FieldType.decimal, required: true),
    FieldSpec('offListNeedsApproval', 'Preço digitado fora da tabela exige autorização do gerente', type: FieldType.boolean),
    FieldSpec('followUpDays', 'Cobrar resposta do orçamento enviado após (dias)', type: FieldType.integer, required: true),
    FieldSpec(
      'approvalValidityDays',
      'Validade da autorização de desconto (dias)',
      type: FieldType.integer,
      required: true,
      hint: 'Passado o prazo sem envio, volta a rascunho',
    ),
    FieldSpec(
      'shippingLocationId',
      'Local de expedição',
      type: FieldType.lookup,
      lookup: LookupSpec('/api/stock-locations'),
      hint: 'Vazio = local de acabado do PCP',
    ),
    FieldSpec('defaultConditions', 'Condições gerais padrão'),
  ];

  Future<List<dynamic>> _fetch() async {
    final api = widget.session.api;
    final r = await Future.wait([
      api.get('/api/stock/settings'),
      api.get('/api/purchasing/settings'),
      api.get('/api/production/settings'),
      api.get('/api/sales/settings'),
    ]);
    final sa = r[3] as Map<String, dynamic>;
    if (sa['shippingLocationId'] is int) sa['shippingLocation'] = await NameCache.name(api, '/api/stock-locations', sa['shippingLocationId'] as int);
    final p = r[1] as Map<String, dynamic>;
    if (p['receivingLocationId'] is int) p['receivingLocation'] = await NameCache.name(api, '/api/stock-locations', p['receivingLocationId'] as int);
    final pr = r[2] as Map<String, dynamic>;
    for (final k in ['issueLocation', 'receiptLocation']) {
      if (pr['${k}Id'] is int) pr[k] = await NameCache.name(api, '/api/stock-locations', pr['${k}Id'] as int);
    }
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
      final pr = r[2] as Map<String, dynamic>;
      final sa = r[3] as Map<String, dynamic>;
      return PageColumn(
        child: ListView(
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
            const SizedBox(height: 12),
            _card('PCP', '/api/production/settings', productionFields, pr, [
              ('Tolerância de excedente', '${fmt(pr['overrunTolerancePercent'])} %'),
              ('Jornada', '${fmt(pr['hoursPerDay'])} h/dia${pr['workSaturdays'] == true ? ' · inclui sábado' : ''}'),
              ('Local de requisição', fmt(pr['issueLocation'] ?? 'ALM (padrão)')),
              ('Entrada de acabado', fmt(pr['receiptLocation'] ?? 'PA (padrão)')),
            ]),
            const SizedBox(height: 12),
            _card('Comercial', '/api/sales/settings', salesFields, sa, [
              ('Desconto sem autorização', 'até ${fmt(sa['maxDiscountPercent'])} %'),
              ('Validade do orçamento', '${fmt(sa['defaultValidityDays'])} dias'),
              ('Faturamento mínimo', (sa['minimumOrderValue'] as num? ?? 0) == 0 ? 'Sem mínimo' : fmtMoney(sa['minimumOrderValue'])),
              ('Preço fora da tabela', sa['offListNeedsApproval'] == true ? 'exige autorização' : 'livre'),
              ('Cobrar resposta', 'após ${fmt(sa['followUpDays'])} dias'),
              ('Validade da autorização', '${fmt(sa['approvalValidityDays'])} dias'),
              ('Local de expedição', fmt(sa['shippingLocation'] ?? 'Acabado do PCP (padrão)')),
              ('Condições gerais', fmt(sa['defaultConditions'])),
            ]),
          ],
        ),
      );
    },
  );
}
