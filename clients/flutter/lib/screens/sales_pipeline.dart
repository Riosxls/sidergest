import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
import 'sales_common.dart';
import 'sales_quotes.dart';

const _stageTones = {
  'quote': Tone.neutral,
  'sent': Tone.info,
  'accepted': Tone.success,
  'order': Tone.info,
  'production': Tone.progress,
  'ready': Tone.success,
  'shipped': Tone.progress,
  'delivered': Tone.success,
};

const _stageIcons = {
  'quote': Icons.edit_note,
  'sent': Icons.send_outlined,
  'accepted': Icons.thumb_up_alt_outlined,
  'order': Icons.receipt_long_outlined,
  'production': Icons.precision_manufacturing_outlined,
  'ready': Icons.inventory_2_outlined,
  'shipped': Icons.local_shipping_outlined,
  'delivered': Icons.task_alt,
};

const _moves = {'quote': 'sent', 'sent': 'accepted', 'accepted': 'order', 'order': 'production'};

class SalesPipelineScreen extends StatefulWidget {
  const SalesPipelineScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesPipelineScreen> createState() => _SalesPipelineScreenState();
}

class _SalesPipelineScreenState extends State<SalesPipelineScreen> {
  int? _customerId;
  late Future<Map<String, dynamic>> _future = _fetch();
  String? _hover;

  ApiClient get api => widget.session.api;
  Session get s => widget.session;

  Future<Map<String, dynamic>> _fetch() async => await api.get('/api/sales/pipeline', {'customerId': _customerId}) as Map<String, dynamic>;

  void _reload() => setState(() {
    _future = _fetch();
  });

  Future<void> _open(Map<String, dynamic> c) async {
    if (c['kind'] == 'Quote') {
      await openQuote(context, s, c['id'] as int);
    } else {
      await openSalesOrder(context, s, c['id'] as int);
    }
    _reload();
  }

  Future<void> _new() async {
    final q = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => QuoteEditorScreen(session: s)));
    if (q != null && mounted) await openQuote(context, s, q['id'] as int);
    _reload();
  }

  Future<void> _advance(Map<String, dynamic> c, String from) async {
    final ref = c['reference'];
    final id = c['id'];
    Future<dynamic>? call;
    String? success;
    switch (from) {
      case 'quote':
        if (!s.canSell) return;
        if (c['status'] == 'PendingApproval') {
          if (!s.canApproveSales) return showError(context, '$ref aguarda aprovação do gerente comercial');
          if (!await confirmStep(
            context,
            title: 'Aprovar desconto de $ref?',
            message: 'A proposta fica liberada para envio ao cliente.',
            confirmLabel: 'Aprovar',
          )) {
            return;
          }
          call = api.post('/api/sales/quotes/$id/approve', {});
          success = 'Desconto aprovado';
          break;
        }
        final q = await api.get('/api/sales/quotes/$id') as Map<String, dynamic>;
        if (!mounted) return;
        final approval = q['status'] == 'Draft' && q['needsApproval'] == true;
        if (!await confirmStep(
          context,
          title: approval ? 'Enviar $ref para aprovação?' : 'Enviar $ref ao cliente?',
          message: approval
              ? 'O desconto passa do limite; o gerente comercial precisa aprovar antes.'
              : 'Será registrada como enviada para ${q['contactEmail'] ?? q['contactName'] ?? 'o contato do cliente'} e a validade começa hoje.',
          confirmLabel: 'Enviar',
          icon: Icons.send,
        )) {
          return;
        }
        call = api.post('/api/sales/quotes/$id/send', {'sentTo': q['contactEmail'] ?? q['contactName']});
        success = approval ? 'Enviada para aprovação' : 'Proposta enviada ao cliente';
      case 'sent':
        if (!s.canSell) return;
        final po = await promptText(context, title: 'Cliente aprovou $ref', label: 'Nº do pedido de compra do cliente', confirmLabel: 'Registrar aprovação');
        if (po == null) return;
        call = api.post('/api/sales/quotes/$id/accept', {'customerPo': po.isEmpty ? null : po});
        success = 'Aprovação do cliente registrada';
      case 'accepted':
        if (!s.canSell) return;
        if (!await confirmStep(
          context,
          title: 'Gerar pedido de venda?',
          message: 'Os itens de $ref viram um pedido de venda.',
          confirmLabel: 'Gerar pedido',
          icon: Icons.receipt_long,
        )) {
          return;
        }
        call = api.post('/api/sales/quotes/$id/convert', {});
        success = 'Pedido de venda criado';
      case 'order':
        if (!s.canReleaseSales) return;
        if (!await confirmStep(
          context,
          title: 'Liberar $ref para produção?',
          message: 'Reserva o estoque livre e cria OFs para o restante.',
          confirmLabel: 'Liberar',
          icon: Icons.precision_manufacturing,
        )) {
          return;
        }
        call = api.post('/api/sales/orders/$id/release', {'useStock': true});
        success = 'Pedido liberado para produção';
      default:
        return _open(c);
    }
    if (!mounted) return;
    await runAction(context, () => call!, success: success);
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureView<Map<String, dynamic>>(
    future: _future,
    onRetry: _reload,
    builder: (context, data) {
      final k = data['kpis'] as Map<String, dynamic>;
      final stages = (data['stages'] as List).cast<Map<String, dynamic>>();
      final winRate = k['winRate'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KpiTile(
                  label: 'Propostas em aberto',
                  value: fmtMoney(k['openQuotesValue']),
                  caption: '${k['openQuotes']} propostas',
                  icon: Icons.request_quote_outlined,
                ),
                KpiTile(
                  label: 'Conversão (90 dias)',
                  value: winRate == null ? '—' : '${((winRate as num) * 100).round()}%',
                  caption: 'aceitas / respondidas',
                  icon: Icons.trending_up,
                  tone: Tone.success,
                ),
                KpiTile(
                  label: 'Pedidos em aberto',
                  value: fmtMoney(k['openOrdersValue']),
                  caption: '${k['openOrders']} pedidos',
                  icon: Icons.receipt_long_outlined,
                  tone: Tone.progress,
                ),
                KpiTile(label: 'Prontos p/ expedir', value: '${k['readyToShip']}', icon: Icons.local_shipping_outlined, tone: Tone.success),
                KpiTile(label: 'Atrasados', value: '${k['lateOrders']}', icon: Icons.schedule, tone: (k['lateOrders'] as num) > 0 ? Tone.danger : Tone.neutral),
                if ((k['pendingApprovals'] as num) > 0)
                  KpiTile(label: 'Aguardando aprovação', value: '${k['pendingApprovals']}', icon: Icons.verified_user_outlined, tone: Tone.warning),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: LookupField(
                    api: api,
                    spec: const LookupSpec('/api/customers'),
                    label: 'Filtrar por cliente',
                    value: _customerId,
                    onChanged: (id, _) {
                      _customerId = id;
                      _reload();
                    },
                  ),
                ),
                IconButton(tooltip: 'Atualizar', onPressed: _reload, icon: const Icon(Icons.refresh)),
                if (s.canSell)
                  FilledButton.icon(key: const ValueKey('pipeline-new'), onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo orçamento')),
                Text('Arraste um cartão para a próxima etapa ou use a seta do cartão.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: ListView(
                key: const ValueKey('kanban'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                children: [for (final st in stages) _column(st)],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _column(Map<String, dynamic> st) {
    final key = st['key'] as String;
    final tone = _stageTones[key] ?? Tone.neutral;
    final cards = (st['cards'] as List).cast<Map<String, dynamic>>();
    final theme = Theme.of(context);
    return DragTarget<(Map<String, dynamic>, String)>(
      onWillAcceptWithDetails: (d) {
        final ok = _moves[d.data.$2] == key;
        setState(() => _hover = ok ? key : null);
        return ok;
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        setState(() => _hover = null);
        _advance(d.data.$1, d.data.$2);
      },
      builder: (context, candidates, _) => Container(
        key: ValueKey('stage-$key'),
        width: 272,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: _hover == key ? toneColors(context, tone).$1 : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border(top: BorderSide(color: toneAccent(context, tone), width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Icon(_stageIcons[key], size: 18, color: toneAccent(context, tone)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(pipelineStages[key] ?? key, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  StatusBadge('${st['count']}', tone: tone),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(fmtMoney(st['value']), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: cards.isEmpty
                  ? Center(child: Text('Nada aqui', style: theme.textTheme.bodySmall))
                  : ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), children: [for (final c in cards) _draggable(c, key)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draggable(Map<String, dynamic> c, String stage) {
    final card = _card(c, stage);
    if (!_moves.containsKey(stage)) return card;
    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 256, child: card),
    );
    final ghost = Opacity(opacity: 0.35, child: card);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return wide
        ? Draggable<(Map<String, dynamic>, String)>(data: (c, stage), feedback: feedback, childWhenDragging: ghost, child: card)
        : LongPressDraggable<(Map<String, dynamic>, String)>(data: (c, stage), feedback: feedback, childWhenDragging: ghost, child: card);
  }

  Widget _card(Map<String, dynamic> c, String stage) {
    final theme = Theme.of(context);
    final badges = (c['badges'] as List).cast<String>();
    final isQuote = c['kind'] == 'Quote';
    final next = _moves[stage];
    return Card(
      key: ValueKey('card-${c['kind']}-${c['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isQuote ? Icons.request_quote_outlined : Icons.receipt_long_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('${c['reference']}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (next != null)
                    IconButton(
                      key: ValueKey('advance-${c['kind']}-${c['id']}'),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Avançar para ${pipelineStages[next]}',
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      onPressed: () => _advance(c, stage),
                    ),
                ],
              ),
              Text('${c['customerName']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fmtMoney(c['value']),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (c['date'] != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '${isQuote ? (c['status'] == 'Sent' ? 'Válida até' : '') : 'Entrega'} ${fmtDay(c['date'])}'.trim(),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                ],
              ),
              if (isQuote && c['status'] != 'Sent' && c['status'] != 'Accepted')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StatusBadge(quoteStatuses[c['status']] ?? '${c['status']}', tone: quoteTone(c['status'])),
                ),
              if (c['progress'] != null && stage == 'production')
                Padding(padding: const EdgeInsets.only(top: 6, right: 6), child: ProgressMeter(c['progress'] as num)),
              if (badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final b in badges)
                        StatusBadge(
                          salesBadges[b] ?? b,
                          tone: switch (b) {
                            'late' => Tone.danger,
                            'discount' || 'expiring' => Tone.warning,
                            'ready' => Tone.success,
                            _ => Tone.info,
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
