import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../entities.dart';
import '../session.dart';
import '../labels.dart';
import '../widgets/dash.dart';
import 'dashboard.dart';
import 'dashboard_data.dart';

class ModuleLink {
  const ModuleLink(this.id, this.icon, this.title);

  final String id;
  final IconData icon;
  final String title;
}

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({super.key, required this.session, required this.module, required this.links, this.onNavigate});

  final Session session;
  final ModuleInfo module;
  final List<ModuleLink> links;
  final Navigate? onNavigate;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  static const _maxWidth = 1280.0;
  late Future<Object> _data = _fetch();
  DateTime? _updated;
  final _focus = FocusNode();
  Timer? _timer;

  String get section => widget.module.section;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _settle();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<Object> _fetch() {
    final api = widget.session.api;
    return switch (section) {
      'Comercial' => fetchCommercial(api),
      'Engenharia' => fetchEngineering(api, dashboardCounted),
      'Estoque' => fetchStock(api),
      'Suprimentos' => fetchPurchasing(api),
      _ => fetchProduction(api, legacyDays: legacyOverdueDays),
    };
  }

  Future<void> _settle() async {
    try {
      await _data;
    } catch (_) {}
    if (mounted) setState(() => _updated = DateTime.now());
  }

  Future<void> _refresh() {
    setState(() => _data = _fetch());
    return _settle();
  }

  void Function()? _go(String id, [String? filter]) => widget.onNavigate == null ? null : () => widget.onNavigate!(id, filter);

  /// [alarm]: a count above zero is a problem, so the tile is drawn red; otherwise it is plain information.
  GridItem _tile(IconData icon, String label, String value, [void Function()? onTap, bool alarm = false]) =>
      GridItem(DashTile(icon: icon, label: label, value: value, alert: alarm && value != '0', onTap: onTap));

  Widget _content(Object data) {
    final items = switch (data) {
      CommercialDashboard d => _commercial(d),
      DashboardData d => _engineering(d),
      StockDashboard d => _stock(d),
      PurchasingDashboard d => _purchasing(d),
      ProductionDashboard d => _production(d),
      _ => <GridItem>[],
    };
    if (items.isEmpty) {
      return const DashNotice(icon: Icons.inbox_outlined, title: 'Sem movimento ainda', subtitle: 'Assim que houver registros, os indicadores aparecem aqui.');
    }
    return DashGrid(items: items);
  }

  List<GridItem> _commercial(CommercialDashboard d) => [
    _tile(Icons.request_quote_outlined, 'Orçamentos abertos', '${d.k('openQuotes').toInt()}', _go('sales-quotes')),
    _tile(Icons.payments_outlined, 'Valor em propostas', fmtMoney(d.k('openQuotesValue')), _go('sales-quotes')),
    _tile(Icons.receipt_long_outlined, 'Pedidos abertos', '${d.k('openOrders').toInt()}', _go('sales-orders')),
    _tile(Icons.attach_money, 'Valor em pedidos', fmtMoney(d.k('openOrdersValue')), _go('sales-orders')),
    _tile(Icons.event_busy_outlined, 'Pedidos atrasados', '${d.k('lateOrders').toInt()}', _go('sales-orders'), true),
    _tile(Icons.local_shipping_outlined, 'Prontos para expedir', '${d.k('readyToShip').toInt()}', _go('deliveries')),
    _tile(Icons.gavel_outlined, 'Aprovações pendentes', '${d.k('pendingApprovals').toInt()}', _go('sales-quotes')),
    _tile(Icons.draw_outlined, 'Viabilidades em assinatura', '${d.feasibilityInReview}', _go('viability', 'InReview')),
    // A rate over no quotes means nothing; show a dash until some quote has been decided or is open.
    _tile(
      Icons.emoji_events_outlined,
      'Taxa de conversão',
      d.kpis['winRate'] == null || (d.k('openQuotes') == 0 && d.stages.values.every((v) => v == 0)) ? '—' : '${((d.kpis['winRate'] as num) * 100).round()}%',
      _go('sales-pipeline'),
    ),
    GridItem.bars(
      BarPanel(
        title: 'Funil por etapa',
        data: {for (final e in d.stages.entries) pipelineStages[e.key] ?? e.key: e.value},
        emptyText: 'Nenhum orçamento ou pedido no funil',
        onRowTap: (_) => _go('sales-pipeline')?.call(),
      ),
    ),
  ];

  List<GridItem> _engineering(DashboardData d) {
    if (d.counts.values.every((v) => v == 0)) return [];
    return [
      for (final e in d.counts.entries) _tile(e.key.icon, e.key.title, '${e.value}', _go(e.key.path)),
      GridItem.bars(BarPanel(title: 'Produtos por tipo', data: _ranked(d.byKind, (k) => kinds[k] ?? '—'))),
      GridItem.bars(BarPanel(title: 'Produtos por formato', data: _ranked(d.byShape, (k) => shapes[k] ?? 'Sem formato'))),
      GridItem.bars(BarPanel(title: 'Operações por produto', data: _operationBuckets(d), warn: const {'0'}, onRowTap: (_) => _go(products.path)?.call())),
    ];
  }

  /// Buckets in reading order (0, 1–3, 4–6, 7+), not sorted by size.
  Map<String, num> _operationBuckets(DashboardData d) => {
    for (final k in const ['0', '1-3', '4-6', '7+'])
      if ((d.operationBuckets[k] ?? 0) > 0) k.replaceAll('-', '–'): d.operationBuckets[k]!,
  };

  /// Server counts relabelled for display, biggest first.
  Map<String, num> _ranked(Map<String, int> counts, String Function(String) label) {
    final m = <String, int>{};
    for (final e in counts.entries) {
      m.update(label(e.key), (v) => v + e.value, ifAbsent: () => e.value);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  List<GridItem> _stock(StockDashboard d) {
    if (d.locations == 0 && d.steelLots == 0) return [];
    return [
      _tile(Icons.trending_down, 'Abaixo do mínimo', '${d.lowStock.length}', _go('low-stock'), d.lowStock.isNotEmpty),
      _tile(Icons.verified_outlined, 'Lotes em quarentena', '${d.quarantine}', _go('lots', 'Quarantine'), true),
      _tile(Icons.bookmark_border, 'Reservas abertas', '${d.openReservations}', _go('reservations')),
      _tile(Icons.lock_outline, 'Último mês fechado', d.lastClosing == null ? 'Nenhum' : fmtPeriod(d.lastClosing!['period']), _go('closing')),
      // A failed steel lookup shows a dash, not a believable zero.
      _tile(Icons.layers_outlined, 'Bobinas de aço', d.steelUnavailable ? '—' : '${d.steelLots}', _go('steel')),
      _tile(Icons.scale_outlined, 'Saldo de aço (kg)', d.steelUnavailable ? '—' : fmt(d.steelBalanceKg), _go('steel')),
      _tile(Icons.payments_outlined, 'Saldo de aço (R\$)', d.steelUnavailable ? '—' : fmtMoney(d.steelBalanceValue), _go('steel')),
      _tile(Icons.content_cut, 'No slitter', d.steelUnavailable ? '—' : '${d.steelPending}', _go('steel')),
    ];
  }

  List<GridItem> _purchasing(PurchasingDashboard d) {
    if (d.pendingApproval + d.approved + d.openQuotations + d.openOrders + d.overdue.length == 0) return [];
    final fresh = d.overdue.where((l) => (l['daysLate'] as num) <= legacyOverdueDays).toList();
    final legacy = d.overdue.where((l) => (l['daysLate'] as num) > legacyOverdueDays).toList();
    final perf = {for (final p in d.performance.where((p) => (p['receivedLines'] as num) > 0)) '${p['supplierName']}': p['onTimePercent'] as num};
    return [
      _tile(Icons.assignment_late_outlined, 'Requisições a aprovar', '${d.pendingApproval}', _go('requisitions', 'PendingApproval')),
      _tile(Icons.assignment_turned_in_outlined, 'Aprovadas sem cotação', '${d.approved}', _go('requisitions', 'Approved')),
      _tile(Icons.request_quote_outlined, 'Cotações abertas', '${d.openQuotations}', _go('quotations')),
      _tile(Icons.receipt_long_outlined, 'Pedidos abertos', '${d.openOrders}', _go('orders')),
      _tile(Icons.schedule, 'Entregas em atraso', '${fresh.length}', _go('overdue'), true),
      _tile(Icons.history, 'Atrasadas há mais de $legacyOverdueDays dias', '${legacy.length}', _go('overdue')),
      GridItem.bars(
        BarPanel(
          title: 'Atrasos recentes por fornecedor',
          data: d.overdueBySupplierOf(fresh),
          emptyText: 'Nenhuma entrega atrasada nos últimos $legacyOverdueDays dias',
          onRowTap: (_) => _go('overdue')?.call(),
        ),
      ),
      GridItem.bars(
        BarPanel(
          title: 'Pontualidade 12 meses (%)',
          data: perf,
          max: 100,
          emptyText: 'Sem recebimentos com data prevista nos últimos 12 meses',
          onRowTap: (_) => _go('suppliers')?.call(),
        ),
      ),
    ];
  }

  List<GridItem> _production(ProductionDashboard d) {
    if (d.openTotal == 0 && d.shipments.isEmpty) return [];
    return [
      _tile(Icons.assignment_outlined, 'OFs a liberar', '${d.count('Created')}', _go('production-orders', 'Created')),
      _tile(Icons.play_circle_outline, 'Liberadas', '${d.count('Released')}', _go('production-orders', 'Released')),
      _tile(Icons.precision_manufacturing_outlined, 'Em produção', '${d.count('InProduction')}', _go('production-orders', 'InProduction')),
      _tile(Icons.pause_circle_outline, 'Paradas', '${d.count('Stopped')}', _go('production-orders', 'Stopped'), true),
      _tile(Icons.schedule, 'Atrasadas', '${d.lateFresh.total}', _go('production-orders'), true),
      _tile(Icons.history, 'Atrasadas há mais de $legacyOverdueDays dias', '${d.lateLegacy.total}', _go('production-orders')),
      _tile(Icons.outbox_outlined, 'Remessas em terceiros', '${d.shipments.length}', _go('outside-processing')),
      GridItem.bars(
        BarPanel(
          title: 'Pico de carga 4 semanas (%)',
          data: d.peakLoad,
          emptyText: 'Nenhuma OF programada nas próximas 4 semanas',
          onRowTap: (_) => _go('planning')?.call(),
        ),
      ),
    ];
  }

  Widget _links() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // With the sidebar showing, the same screens are one click away; keep them as a compact row under the data instead of a wall of cards.
    if (MediaQuery.sizeOf(context).width >= 900) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in widget.links)
            ActionChip(
              key: ValueKey('link-${l.id}'),
              avatar: Icon(l.icon, size: 18, color: cs.primary),
              label: Text(l.title),
              onPressed: _go(l.id),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final cols = (((c.maxWidth + gap) / (220 + gap)).floor()).clamp(1, 6);
        final width = (c.maxWidth - gap * (cols - 1)) / cols - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final l in widget.links)
              SizedBox(
                width: width,
                height: 64,
                child: Card(
                  key: ValueKey('link-${l.id}'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: dashCardShape(context),
                  color: cs.surfaceContainerHigh,
                  child: InkWell(
                    onTap: _go(l.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(l.icon, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updated = _updated;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f5): _refresh},
      child: Focus(
        focusNode: _focus,
        child: PullRefresh(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The app bar already names the module; this row carries what it is for and when the numbers were read.
                    Row(
                      children: [
                        Icon(widget.module.icon, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(widget.module.blurb, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        if (updated != null) Text('Atualizado às ${hhmm(updated)}', style: theme.textTheme.bodySmall),
                        IconButton(tooltip: 'Atualizar (F5)', onPressed: _refresh, icon: const Icon(Icons.refresh)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Indicadores', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    FutureBuilder<Object>(
                      future: _data,
                      builder: (context, snap) {
                        if (snap.hasError) return Text(friendlyError(snap.error!), style: TextStyle(color: theme.colorScheme.error));
                        if (!snap.hasData) return const LinearProgressIndicator();
                        return _content(snap.data!);
                      },
                    ),
                    const SizedBox(height: 24),
                    Text('Telas', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _links(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
