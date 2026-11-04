import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../theme_tokens.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/responsive.dart';
import 'certificates.dart';
import 'sales_common.dart';
import 'sales_quotes.dart';

const _stageTones = {
  'quote': Tone.neutral,
  'sent': Tone.info,
  'accepted': Tone.success,
  'po': Tone.success,
  'order': Tone.info,
  'production': Tone.progress,
  'certificate': Tone.warning,
  'ready': Tone.success,
  'shipped': Tone.progress,
  'delivered': Tone.success,
};

const _stageIcons = {
  'quote': Icons.edit_note,
  'sent': Icons.send_outlined,
  'accepted': Icons.thumb_up_alt_outlined,
  'po': Icons.assignment_turned_in_outlined,
  'order': Icons.receipt_long_outlined,
  'production': Icons.precision_manufacturing_outlined,
  'certificate': Icons.verified_outlined,
  'ready': Icons.inventory_2_outlined,
  'shipped': Icons.local_shipping_outlined,
  'delivered': Icons.task_alt,
};

const _moves = {'quote': 'sent', 'sent': 'accepted', 'accepted': 'po', 'po': 'order', 'order': 'production', 'certificate': 'ready'};

/// The 8-step sales pipeline (Orçamento to Entrega).
class SalesPipelineScreen extends StatefulWidget {
  const SalesPipelineScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesPipelineScreen> createState() => _SalesPipelineScreenState();
}

class _SalesPipelineScreenState extends State<SalesPipelineScreen> {
  int? _customerId;
  String? _hover;

  /// Stage the dragged card comes from; the columns that cannot take it are dimmed meanwhile.
  String? _dragFrom;
  final _kanbanScroll = ScrollController();

  /// Last data stays on screen while a reload runs, so the board does not blank and the scroll position is kept.
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _kanbanScroll.dispose();
    super.dispose();
  }

  ApiClient get api => widget.session.api;
  Session get s => widget.session;

  Future<void> _reload() async {
    if (!mounted) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await api.get('/api/sales/pipeline', {'customerId': _customerId}) as Map<String, dynamic>;
      if (mounted && seq == _seq) {
        setState(() {
          _data = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    if (c['kind'] == 'Quote') {
      await openQuote(context, s, c['id'] as int);
    } else {
      await openSalesOrder(context, s, c['id'] as int);
    }
    unawaited(_reload());
  }

  Future<void> _new() async {
    await newQuote(context, s);
    unawaited(_reload());
  }

  /// The lookups before a step (quote, drafts, order) can fail; the error is shown instead of leaving the click without any answer.
  Future<void> _advance(Map<String, dynamic> c, String from) async {
    try {
      await _advanceStep(c, from);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _advanceStep(Map<String, dynamic> c, String from) async {
    final ref = c['reference'];
    final id = c['id'];
    Future<dynamic>? call;
    String? success;
    switch (from) {
      case 'quote':
        if (!s.canSell) return;
        if (c['status'] == 'PendingApproval') {
          if (!s.canApproveSales) return showError(context, '$ref aguarda autorização do gerente comercial');
          if (!await confirmStep(
            context,
            title: 'Autorizar desconto de $ref?',
            message: 'O orçamento fica liberado para envio ao cliente.',
            confirmLabel: 'Autorizar',
          )) {
            return;
          }
          call = api.post('/api/sales/quotes/$id/approve', {});
          success = 'Desconto autorizado';
          break;
        }
        final q = await api.get('/api/sales/quotes/$id') as Map<String, dynamic>;
        if (!mounted) return;
        final approval = q['status'] == 'Draft' && q['needsApproval'] == true;
        if (!await confirmStep(
          context,
          title: approval ? 'Enviar $ref para autorização?' : 'Enviar $ref ao cliente?',
          message: approval
              ? 'O desconto passa do limite; o gerente comercial precisa autorizar antes.'
              : 'Será registrada como enviada para ${q['contactEmail'] ?? q['contactName'] ?? 'o contato do cliente'} e a validade começa hoje.',
          confirmLabel: 'Enviar',
          icon: Icons.send,
        )) {
          return;
        }
        call = api.post('/api/sales/quotes/$id/send', {'sentTo': q['contactEmail'] ?? q['contactName']});
        success = approval ? 'Enviada para autorização' : 'Orçamento enviado ao cliente';
      case 'sent':
        if (!s.canSell) return;
        call = api.post('/api/sales/quotes/$id/accept', {});
        success = 'Aprovação do cliente registrada';
      case 'accepted':
        if (!s.canSell) return;
        // The purchase order file/text is attached on the quote itself.
        await openQuote(context, s, id as int);
        return _reload();
      case 'po':
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
      case 'certificate':
        if (!s.canCertificate) return;
        final drafts = await api.list('/api/sales/certificates', query: {'orderId': id, 'status': 'Draft'});
        if (!mounted) return;
        if (drafts.items.isNotEmpty) {
          await openCertificate(context, s, drafts.items.first['id'] as int);
        } else {
          final order = await api.get('/api/sales/orders/$id') as Map<String, dynamic>;
          if (!mounted) return;
          await newCertificate(context, s, order);
        }
        return _reload();
      default:
        return _open(c);
    }
    if (!mounted) return;
    await runAction(context, () => call!, success: success);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterBar(context),
        SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
        if (data == null)
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(friendlyError(_error!)), TextButton(onPressed: _reload, child: const Text('Tentar novamente'))],
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(friendlyError(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  TextButton(onPressed: _reload, child: const Text('Tentar novamente')),
                ],
              ),
            ),
          _kpis(data['kpis'] as Map<String, dynamic>),
          Expanded(
            child: Scrollbar(
              controller: _kanbanScroll,
              child: ListView(
                key: const ValueKey('kanban'),
                controller: _kanbanScroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                children: [for (final st in (data['stages'] as List).cast<Map<String, dynamic>>()) _column(st)],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Filters and actions stay mounted while the board reloads, so the customer field keeps its focus and text.
  Widget _filterBar(BuildContext context) {
    final touch = isTouchPlatform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
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
                unawaited(_reload());
              },
            ),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh)),
          Tooltip(
            // A phone has no mouse to drag with: the card is held (long press) before it moves.
            message: touch
                ? 'Segure um cartão e arraste para a próxima etapa, ou use a seta do cartão.'
                : 'Arraste um cartão para a próxima etapa ou use a seta do cartão.',
            triggerMode: TooltipTriggerMode.tap,
            child: const Padding(padding: EdgeInsets.all(AppSpacing.sm), child: Icon(Icons.info_outline, size: 20)),
          ),
          if (s.canSell)
            FilledButton.icon(key: const ValueKey('pipeline-new'), onPressed: _new, icon: const Icon(Icons.add), label: const Text('Novo orçamento')),
        ],
      ),
    );
  }

  /// Four figures only; conversion rides on the quotes tile and the approvals tile shows up only when something waits.
  Widget _kpis(Map<String, dynamic> k) {
    final winRate = k['winRate'];
    final conversion = winRate == null ? '' : ' · conversão ${((winRate as num) * 100).round()}% (90 dias)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          KpiTile(
            label: 'Orçamentos em aberto',
            value: fmtMoney(k['openQuotesValue']),
            caption: '${k['openQuotes']} orçamentos$conversion',
            icon: Icons.request_quote_outlined,
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
            KpiTile(label: 'Aguardando autorização', value: '${k['pendingApprovals']}', icon: Icons.verified_user_outlined, tone: Tone.warning),
        ],
      ),
    );
  }

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
      builder: (context, candidates, _) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _dragFrom != null && _dragFrom != key && _moves[_dragFrom] != key ? 0.45 : 1,
        child: Container(
        key: ValueKey('stage-$key'),
        width: 272,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: _hover == key ? toneColors(context, tone).$1 : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.card),
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
    void start() => setState(() => _dragFrom = stage);
    void end() {
      if (mounted) setState(() => _dragFrom = null);
    }

    return wide
        ? Draggable<(Map<String, dynamic>, String)>(
            data: (c, stage),
            feedback: feedback,
            childWhenDragging: ghost,
            onDragStarted: start,
            onDragEnd: (_) => end(),
            child: card,
          )
        : LongPressDraggable<(Map<String, dynamic>, String)>(
            data: (c, stage),
            feedback: feedback,
            childWhenDragging: ghost,
            onDragStarted: start,
            onDragEnd: (_) => end(),
            child: card,
          );
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
                      constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
                      tooltip: 'Avançar para ${pipelineStages[next]}',
                      icon: const Icon(Icons.arrow_forward, size: 20),
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
                          '${isQuote ? (c['status'] == 'Sent' ? 'Válida até' : 'Criada em') : 'Entrega'} ${fmtDay(c['date'])}',
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                ],
              ),
              if (isQuote && c['status'] != 'Sent' && c['status'] != 'PurchaseOrder' && c['status'] != 'Accepted')
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
                            'discount' || 'expiring' || 'followup' => Tone.warning,
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
