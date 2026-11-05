import 'dart:async';

import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/pipeline.dart';
import '../widgets/record_list.dart';
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
  late Future<Map<String, dynamic>> _future = _fetch();
  String? _hover;
  final _kanbanScroll = ScrollController();

  /// Whether the server can send e-mail (SMTP set up): then "send to the customer" opens the quote screen and its e-mail dialog.
  late final Future<bool> _mailOn = _fetchMailOn();

  Future<bool> _fetchMailOn() async {
    try {
      final r = await api.get('/api/system/mail');
      return r is Map<String, dynamic> && r['enabled'] == true;
    } catch (e) {
      debugPrint('sales_pipeline: mail status lookup failed, a send is only registered: $e');
      return false;
    }
  }

  static const _columnWidth = 272.0;
  static const _columnGap = 10.0;

  /// A mouse wheel only scrolls up and down; over the kanban (outside a column that has more cards to scroll) it moves the columns sideways.
  void _wheelToHorizontal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.scrollDelta.dy == 0 || !_kanbanScroll.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final p = _kanbanScroll.position;
      _kanbanScroll.jumpTo((p.pixels + (event as PointerScrollEvent).scrollDelta.dy).clamp(p.minScrollExtent, p.maxScrollExtent));
    });
  }

  void _jumpTo(int column) {
    if (!_kanbanScroll.hasClients) return;
    final p = _kanbanScroll.position;
    unawaited(_kanbanScroll.animateTo((column * (_columnWidth + _columnGap)).clamp(p.minScrollExtent, p.maxScrollExtent), duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _kanbanScroll.dispose();
    super.dispose();
  }

  ApiClient get api => widget.session.api;
  Session get s => widget.session;

  /// "1 orçamento", "3 orçamentos".
  static String _count(Object? n, String one, String many) => '$n ${n == 1 ? one : many}';

  /// A phone or a touch tablet has no mouse: cards are held (long press) before they move, so a swipe still scrolls.
  bool get _touch => const {TargetPlatform.android, TargetPlatform.iOS}.contains(Theme.of(context).platform);

  Future<Map<String, dynamic>> _fetch() async => await api.get('/api/sales/pipeline', {'customerId': _customerId}) as Map<String, dynamic>;

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _open(Map<String, dynamic> c) async {
    if (c['kind'] == 'Quote') {
      await openQuote(context, s, c['id'] as int);
    } else {
      await openSalesOrder(context, s, c['id'] as int);
    }
    _reload();
  }

  Future<void> _new() async {
    await newQuote(context, s);
    _reload();
  }

  /// The lookups before a step (quote, drafts, order) can fail; the error is shown instead of leaving the click without any answer.
  Future<void> _advance(Map<String, dynamic> c, String from) async {
    try {
      await _advanceStep(c, from);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  /// Whether this user may move a card out of [stage]; the arrow and the drag exist only for those who may, so a click is never silently ignored.
  bool _canAdvance(String stage) => switch (stage) {
    'quote' || 'sent' || 'accepted' || 'po' => s.canSell,
    'order' => s.canReleaseSales,
    'certificate' => s.canCertificate,
    _ => false,
  };

  Future<void> _advanceStep(Map<String, dynamic> c, String from) async {
    final ref = c['reference'];
    final id = c['id'];
    Future<dynamic>? call;
    String? success;
    // A move that reaches this point without the permission (a stale card, a role change) is answered, not ignored.
    if (!_canAdvance(from)) return showError(context, 'Sem permissão para esta etapa');
    switch (from) {
      case 'quote':
        if (c['status'] == 'PendingApproval') {
          if (!s.canApproveSales) return showError(context, '$ref aguarda aprovação do gerente comercial');
          if (!await confirmStep(
            context,
            title: 'Aprovar desconto de $ref?',
            message: 'O orçamento fica liberado para envio ao cliente.',
            confirmLabel: 'Aprovar',
          )) {
            return;
          }
          call = api.post('/api/sales/quotes/$id/approve', {});
          success = 'Desconto aprovado';
          break;
        }
        final q = await api.get('/api/sales/quotes/$id') as Map<String, dynamic>;
        final mail = await _mailOn;
        if (!mounted) return;
        final approval = q['status'] == 'Draft' && q['needsApproval'] == true;
        if (!approval && mail) {
          // The system sends the e-mail with the PDF from the quote screen: opening it there keeps the e-mail dialog, instead of only registering a send.
          await openQuote(context, s, id as int);
          return _reload();
        }
        final to = q['contactEmail'] ?? q['contactName'] ?? 'o contato do cliente';
        if (!await confirmStep(
          context,
          title: approval ? 'Enviar $ref para aprovação?' : 'Registrar envio de $ref?',
          message: approval
              ? 'O desconto passa do limite; o gerente comercial precisa aprovar antes.'
              : 'O sistema não envia e-mail: isto só registra que o orçamento foi enviado para $to e a validade começa hoje. Envie o PDF pelo seu programa de e-mail.',
          confirmLabel: approval ? 'Enviar' : 'Registrar envio',
          icon: Icons.send,
        )) {
          return;
        }
        call = api.post('/api/sales/quotes/$id/send', {'sentTo': q['contactEmail'] ?? q['contactName']});
        success = approval ? 'Enviada para aprovação' : 'Envio registrado (o sistema não envia e-mail)';
      case 'sent':
        // The approval starts the delivery-time clock: same confirmation (with the date) as on the quote screen.
        if (!await confirmCustomerApproval(context, '$ref')) return;
        call = api.post('/api/sales/quotes/$id/accept', {});
        success = 'Aprovação do cliente registrada';
      case 'accepted':
        // The purchase order file/text is attached on the quote itself.
        await openQuote(context, s, id as int);
        return _reload();
      case 'po':
        if (!await confirmStep(
          context,
          title: 'Gerar pedido de venda?',
          message: 'Os itens de $ref viram um pedido de venda. O limite de crédito do cliente é verificado agora.',
          confirmLabel: 'Gerar pedido',
          icon: Icons.receipt_long,
        )) {
          return;
        }
        if (!mounted) return;
        // The credit limit may refuse it: a manager is offered the override, anyone else is told whom to ask.
        final order = await convertQuote(context, s, id as int);
        if (order != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido ${order['reference']} criado')));
        return _reload();
      case 'order':
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
                  label: 'Orçamentos em aberto',
                  value: fmtMoney(k['openQuotesValue']),
                  caption: _count(k['openQuotes'], 'orçamento', 'orçamentos'),
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
                  caption: _count(k['openOrders'], 'pedido', 'pedidos'),
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
                // Someone who cannot move cards (a reader) is not told to.
                if (stages.any((st) => _canAdvance(st['key'] as String)))
                  Text(
                    _touch
                        ? 'Segure um cartão e arraste para a próxima etapa, ou use a seta do cartão.'
                        : 'Arraste um cartão para a próxima etapa ou use a seta do cartão.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          // The columns run wider than the window: a chip per stage (with how many cards it holds) jumps to it.
          SizedBox(
            height: 40,
            child: ListView(
              key: const ValueKey('stage-chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (i, st) in stages.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: ValueKey('stage-chip-${st['key']}'),
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(_stageIcons[st['key']], size: 16),
                      label: Text('${pipelineStages[st['key']] ?? st['key']} · ${st['count']}'),
                      onPressed: () => _jumpTo(i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: _wheelToHorizontal,
              child: Scrollbar(
                controller: _kanbanScroll,
                child: ListView(
                  key: const ValueKey('kanban'),
                  controller: _kanbanScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  children: [for (final st in stages) _column(st)],
                ),
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
        width: _columnWidth,
        margin: const EdgeInsets.only(right: _columnGap),
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
    // No drag for a user who may not move the card out of this stage.
    if (!_moves.containsKey(stage) || !_canAdvance(stage)) return card;
    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 256, child: card),
    );
    final ghost = Opacity(opacity: 0.35, child: card);
    // A touch tablet is wide too, but a swipe on it must scroll the columns, not grab a card: touch always means long press.
    final wide = MediaQuery.sizeOf(context).width >= 900 && !_touch;
    return wide
        ? Draggable<(Map<String, dynamic>, String)>(data: (c, stage), feedback: feedback, childWhenDragging: ghost, child: card)
        : LongPressDraggable<(Map<String, dynamic>, String)>(data: (c, stage), feedback: feedback, childWhenDragging: ghost, child: card);
  }

  /// A card badge. The quote alerts (discount, expiring, follow-up) are the ones of the quote list ([quoteAlertSpecs]); the order ones are its own.
  Widget _badge(String b) {
    final alert = quoteAlertSpecs[b];
    if (alert != null) return StatusBadge(alert.text, tone: alert.tone, icon: alert.icon);
    return StatusBadge(
      salesBadges[b] ?? b,
      tone: switch (b) {
        'late' => Tone.danger,
        'ready' => Tone.success,
        _ => Tone.info,
      },
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
                  if (next != null && _canAdvance(stage))
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
                      for (final b in badges) FittedBox(fit: BoxFit.scaleDown, child: _badge(b)), // a long name shrinks instead of overflowing the card
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
