import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart' show showError;
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';

Tone feasibilityTone(Object? s) => switch (s) {
  'Draft' => Tone.neutral,
  'InReview' => Tone.warning,
  'Approved' => Tone.success,
  _ => Tone.danger,
};

(int, String?) feasibilityPath(Object? s) => switch (s) {
  'Draft' => (0, null),
  'InReview' => (1, null),
  'Approved' => (2, null),
  _ => (1, 'Reprovada'),
};

const _steps = [
  PathStep('Rascunho', icon: Icons.edit_note),
  PathStep('Assinaturas', icon: Icons.draw_outlined),
  PathStep('Aprovada', icon: Icons.verified_outlined),
];

const feasibilityFields = [
  FieldSpec('customerId', 'Cliente', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/customers')),
  FieldSpec('quoteId', 'Proposta', type: FieldType.lookup, lookup: LookupSpec('/api/sales/quotes'), hint: 'Opcional; os pedidos da proposta herdam a análise'),
  FieldSpec('productId', 'Produto', type: FieldType.lookup, lookup: LookupSpec('/api/products')),
  FieldSpec('title', 'Título', required: true, hint: 'Ex.: Tubo Ø25,4 x 1,5 – DIN 2393'),
  FieldSpec('characteristics', 'Características'),
  FieldSpec('transformations', 'Transformações', hint: 'Corte, furação, dobra…'),
  FieldSpec('finishing', 'Acabamento'),
  FieldSpec('packaging', 'Embalagem'),
  FieldSpec('monthlyConsumptionKg', 'Consumo mensal estimado (kg)', type: FieldType.decimal),
  FieldSpec('ordersAllowed', 'Pedidos cobertos', type: FieldType.integer, defaultValue: 3),
];

Future<void> openFeasibility(BuildContext context, Session session, int id) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => FeasibilityScreen(session: session, id: id),
  ),
);

Future<Map<String, dynamic>?> newFeasibility(BuildContext context, Session session, {Map<String, dynamic>? initial}) {
  final api = session.api;
  return submitForm(
    context,
    api: api,
    title: 'Nova análise de viabilidade',
    fields: feasibilityFields,
    initial: initial,
    submit: (b) => api.post('/api/viability', b),
  );
}

class ViabilityScreen extends StatefulWidget {
  const ViabilityScreen({super.key, required this.session, this.initialStatus});

  final Session session;
  final String? initialStatus;

  @override
  State<ViabilityScreen> createState() => _ViabilityScreenState();
}

class _ViabilityScreenState extends State<ViabilityScreen> {
  final _list = GlobalKey<RecordListState>();
  late String? _status = widget.initialStatus;

  Future<void> _new() async {
    final r = await newFeasibility(context, widget.session);
    _list.currentState?.reload();
    if (r == null || r['id'] is! int || !mounted) return;
    await openFeasibility(context, widget.session, r['id'] as int);
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => RecordList(
    key: _list,
    api: widget.session.api,
    path: '/api/viability',
    query: {'status': _status},
    searchHint: 'FAV, título ou cliente',
    filters: [ChoiceFilter(label: 'Situação', value: _status, choices: feasibilityStatuses, onChanged: (v) => setState(() => _status = v))],
    fab: widget.session.canSell
        ? FloatingActionButton.extended(heroTag: 'new-feasibility', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nova análise'))
        : null,
    columns: [
      col('FAV', 'reference'),
      col('Título', 'title'),
      col('Cliente', 'customerName'),
      col('Proposta', 'quoteReference'),
      col('Produto', 'productCode'),
      labelCol('Situação', 'status', feasibilityStatuses),
      ColumnSpec('Assinaturas', (e) => '${e['signed']}/3', numeric: true),
      ColumnSpec('Pedidos', (e) => '${e['ordersUsed']}/${e['ordersAllowed']}', numeric: true),
      col('Consumo (kg/mês)', 'monthlyConsumptionKg', numeric: true),
    ],
    onTap: (e) async {
      await openFeasibility(context, widget.session, e['id'] as int);
      _list.currentState?.reload();
    },
  );
}

class FeasibilityScreen extends StatefulWidget {
  const FeasibilityScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<FeasibilityScreen> createState() => _FeasibilityScreenState();
}

class _FeasibilityScreenState extends State<FeasibilityScreen> {
  Map<String, dynamic>? _f;
  String? _error;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/viability/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _f = f;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _post(String path, {Object? body, String? success}) async {
    final r = await runAction(context, () => api.post('$base/$path', body ?? <String, dynamic>{}), success: success);
    if (r is Map<String, dynamic>) setState(() => _f = r);
  }

  Future<void> _edit() async {
    final f = _f!;
    final r = await submitForm(
      context,
      api: api,
      title: 'Editar ${f['reference']}',
      fields: feasibilityFields,
      initial: {
        for (final k in [
          'customerId',
          'quoteId',
          'productId',
          'title',
          'characteristics',
          'transformations',
          'finishing',
          'packaging',
          'monthlyConsumptionKg',
          'ordersAllowed',
        ])
          k: f[k],
        '_labels': {
          'customerId': '${f['customerName']}',
          if (f['quoteId'] != null) 'quoteId': '${f['quoteReference']}',
          if (f['productId'] != null) 'productId': '${f['productCode']} · ${f['productName']}',
        },
      },
      submit: (b) => api.put(base, b),
    );
    if (r != null && r['reference'] != null) setState(() => _f = r);
  }

  Future<void> _sign(String area) async {
    final note = await promptText(context, title: 'Assinar pela ${signoffAreas[area]}', label: 'Observação (opcional)', confirmLabel: 'Assinar');
    if (note == null || !mounted) return;
    await _post('sign/${area.toLowerCase()}', body: {'note': note.isEmpty ? null : note}, success: 'Assinatura registrada');
  }

  Future<void> _reject(String area) async {
    final reason = await promptText(context, title: 'Reprovar pela ${signoffAreas[area]}', label: 'Motivo', required: true, confirmLabel: 'Reprovar');
    if (reason == null || !mounted) return;
    await _post('reject/${area.toLowerCase()}', body: {'note': reason});
  }

  Future<void> _reopen() async {
    final ok = await confirmStep(
      context,
      title: 'Reabrir ${_f!['reference']}?',
      message: 'As assinaturas são apagadas e a análise volta a rascunho.',
      confirmLabel: 'Reabrir',
    );
    if (ok && mounted) await _post('reopen');
  }

  Future<void> _delete() async {
    final ok = await confirmStep(
      context,
      title: 'Excluir ${_f!['reference']}?',
      message: 'Só rascunhos podem ser excluídos.',
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

  bool _may(String area) => switch (area) {
    'Quality' => s.canSignQuality,
    'Production' => s.canSignProduction,
    _ => s.canSignCommercial,
  };

  Widget _nextStep(Map<String, dynamic> f) {
    final signed = (f['signoffs'] as List).where((x) => (x as Map)['at'] != null).length;
    return switch (f['status']) {
      'Draft' => NextStepCard(
        title: 'Enviar para análise',
        message: 'Depois de enviada, Qualidade, Produção e Comercial assinam cada um a sua parte.',
        actions: [
          if (s.canSell)
            FilledButton.icon(
              key: const ValueKey('fav-submit'),
              onPressed: () => _post('submit', success: 'Enviada para análise'),
              icon: const Icon(Icons.send),
              label: const Text('Enviar para análise'),
            ),
        ],
      ),
      'InReview' => NextStepCard(
        title: 'Aguardando assinaturas · $signed de 3',
        message: 'A análise só vale quando as três áreas assinarem.',
        tone: Tone.warning,
      ),
      'Approved' => NextStepCard(
        title: 'Aprovada',
        message:
            'Vale para ${f['ordersRemaining']} de ${f['ordersAllowed']} pedidos do mesmo item. Ao lançar o pedido, escolha esta análise na linha; ela alimenta o roteiro da OF.',
        tone: Tone.success,
      ),
      _ => NextStepCard(title: 'Reprovada', message: '${f['rejectionReason'] ?? ''}', tone: Tone.danger),
    };
  }

  Widget _signoff(Map<String, dynamic> f, Map<String, dynamic> x) {
    final theme = Theme.of(context);
    final area = '${x['area']}';
    final signed = x['at'] != null;
    final open = f['status'] == 'InReview' && !signed && _may(area);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  signed ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: signed ? toneAccent(context, Tone.success) : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(signoffAreas[area] ?? area, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(signed ? '${fmt(x['by'])} · ${fmtDate(x['at'])}' : 'Pendente', style: theme.textTheme.bodySmall),
            if (x['note'] != null) Text('${x['note']}', style: theme.textTheme.bodySmall),
            if (open) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(key: ValueKey('sign-$area'), onPressed: () => _sign(area), child: const Text('Assinar')),
                  TextButton(key: ValueKey('reject-$area'), onPressed: () => _reject(area), child: const Text('Reprovar')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final status = '${f?['status']}';
    final menu = <PopupMenuEntry<VoidCallback>>[
      if (s.canSell && ['Draft', 'Rejected'].contains(status))
        PopupMenuItem(
          value: _edit,
          child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar')),
        ),
      if (s.canSell && status != 'Draft' && f != null && (f['ordersUsed'] as int) == 0)
        PopupMenuItem(
          value: _reopen,
          child: const ListTile(leading: Icon(Icons.undo), title: Text('Reabrir')),
        ),
      if (s.canSell && status == 'Draft')
        PopupMenuItem(
          value: _delete,
          child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir')),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(f == null ? 'Análise de viabilidade' : '${f['reference']} · ${f['title']}', overflow: TextOverflow.ellipsis),
        actions: [if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(key: const ValueKey('fav-menu'), onSelected: (v) => v(), itemBuilder: (_) => menu)],
      ),
      body: _error != null && f == null
          ? Center(child: Text(_error!))
          : f == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(f)),
    );
  }

  Widget _body(Map<String, dynamic> f) {
    final (step, failed) = feasibilityPath(f['status']);
    final orders = (f['orders'] as List).cast<Map<String, dynamic>>();
    final used = f['ordersUsed'] as int, allowed = f['ordersAllowed'] as int;
    return SideBySide(
      main: [
        RecordHeader(
          icon: Icons.fact_check_outlined,
          kind: 'Análise de viabilidade',
          title: '${f['reference']}',
          badge: StatusBadge(feasibilityStatuses[f['status']] ?? '${f['status']}', tone: feasibilityTone(f['status'])),
          fields: [
            ('Cliente', '${f['customerName']}'),
            ('Proposta', fmt(f['quoteReference'])),
            ('Produto', f['productCode'] == null ? '' : '${f['productCode']} · ${f['productName']}'),
            ('Consumo mensal (kg)', fmt(f['monthlyConsumptionKg'])),
          ],
        ),
        gap,
        StagePath(steps: _steps, current: step, failedLabel: failed),
        gap,
        _nextStep(f),
        gap,
        Section(
          title: 'Assinaturas',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final x in (f['signoffs'] as List).cast<Map<String, dynamic>>()) SizedBox(width: 260, child: _signoff(f, x))],
          ),
        ),
        gap,
        Section(
          title: 'Cobertura de pedidos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProgressMeter(allowed == 0 ? 0 : used / allowed, label: '$used de $allowed pedidos usados'),
              const SizedBox(height: 8),
              if (orders.isEmpty) const Text('Nenhum pedido usa esta análise ainda.'),
              for (final o in orders)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${o['reference']}'),
                  trailing: StatusBadge(salesOrderStatuses[o['status']] ?? '${o['status']}', tone: orderTone(o['status'])),
                  onTap: () => openSalesOrder(context, s, o['orderId'] as int).then((_) => _load()),
                ),
            ],
          ),
        ),
        gap,
        Section(
          title: 'Características e processo',
          child: InfoGrid([
            ('Características', fmt(f['characteristics'])),
            ('Transformações', fmt(f['transformations'])),
            ('Acabamento', fmt(f['finishing'])),
            ('Embalagem', fmt(f['packaging'])),
            ('Criada', '${fmt(f['createdBy'])} · ${fmtDate(f['createdAt'])}'),
          ]),
        ),
      ],
      side: [
        Section(
          title: 'Histórico',
          child: TimelineView(
            entries: [
              for (final h in (f['history'] as List).cast<Map<String, dynamic>>())
                TimelineEntry(
                  title: feasibilityActions[h['action']] ?? '${h['action']}',
                  subtitle: h['note'] as String?,
                  user: h['user'] as String?,
                  at: h['at'],
                  tone: '${h['action']}'.startsWith('signed') ? Tone.success : (('${h['action']}'.startsWith('rejected')) ? Tone.danger : Tone.info),
                  icon: '${h['action']}'.startsWith('signed') ? Icons.draw : Icons.circle,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
