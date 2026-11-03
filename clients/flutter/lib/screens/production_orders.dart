import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../reports/nf_doc.dart';
import '../reports/print_docs.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/discard_guard.dart' show confirmDiscard;
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart' show confirmStep;
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'customers.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'production_cancel_dialog.dart';
import 'production_floor.dart';
import 'sales_common.dart' show openSalesOrder;
import 'stock_documents.dart';
import 'suppliers.dart' show openSupplier;

const openProductionStatuses = ['Created', 'Released', 'Stopped', 'InProduction'];
const runningProductionStatuses = ['Released', 'InProduction'];

bool productionLate(Map<String, dynamic> o) {
  if (!openProductionStatuses.contains(o['status'])) return false;
  if (isLate(o['dueDate'])) return true;
  final end = DateTime.tryParse('${o['adjustedEnd'] ?? o['plannedEnd']}');
  final due = DateTime.tryParse('${o['dueDate']}');
  return end != null && due != null && end.isAfter(due);
}

const productionOrderFields = [
  FieldSpec('productId', 'Produto', type: FieldType.lookup, required: true, lookup: LookupSpec('/api/products')),
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
  FieldSpec('dueDate', 'Data de entrega', type: FieldType.date, required: true),
  FieldSpec('kind', 'Tipo', type: FieldType.choice, choices: productionKinds, required: true, defaultValue: 'Standard'),
  FieldSpec('customerId', 'Cliente', type: FieldType.lookup, lookup: LookupSpec('/api/customers')),
  // Rarely typed by hand: subassemblies are generated from the parent, and the rest is on the paper only.
  FieldSpec(
    'parentOrderId',
    'OF pai',
    type: FieldType.lookup,
    lookup: LookupSpec('/api/production/orders', query: {'open': true}),
    advanced: true,
  ),
  FieldSpec('previousOrderId', 'OF anterior', type: FieldType.lookup, lookup: LookupSpec('/api/production/orders'), advanced: true),
  FieldSpec('bales', 'Amarrados', type: FieldType.integer, advanced: true),
  FieldSpec('primaryTube', 'Tubo primário (perfila)', hint: 'Ex.: Rolo 14,00 x 0,90 mm', advanced: true),
  FieldSpec('notes', 'Observações', advanced: true),
];

const productionUpdateFields = [
  FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true, hint: 'Só altera antes da liberação'),
  FieldSpec('dueDate', 'Data de entrega', type: FieldType.date, required: true),
  FieldSpec('customerId', 'Cliente', type: FieldType.lookup, lookup: LookupSpec('/api/customers')),
  FieldSpec('bales', 'Amarrados', type: FieldType.integer),
  FieldSpec('primaryTube', 'Tubo primário (perfila)', hint: 'Ex.: Rolo 14,00 x 0,90 mm'),
  FieldSpec('notes', 'Observações'),
];

Future<void> openProductionOrder(BuildContext context, Session session, int id) =>
    pushRecord<void>(context, 'production-order', id, (_) => ProductionOrderScreen(session: session, id: id));

Future<void> newProductionOrder(BuildContext context, Session session, {VoidCallback? onSaved}) async {
  final o = await submitForm(
    context,
    api: session.api,
    title: 'Nova ordem de fabricação',
    fields: productionOrderFields,
    submit: (b) => session.api.post('/api/production/orders', b),
  );
  if (o == null) return;
  onSaved?.call();
  if (o['id'] is! int || !context.mounted) return;
  await openProductionOrder(context, session, o['id'] as int);
}

/// List of production orders (OF).
class ProductionOrdersScreen extends StatefulWidget {
  const ProductionOrdersScreen({super.key, required this.session, this.initialStatus});

  final Session session;
  final String? initialStatus;

  @override
  State<ProductionOrdersScreen> createState() => _ProductionOrdersScreenState();
}

class _ProductionOrdersScreenState extends State<ProductionOrdersScreen> {
  final _list = GlobalKey<RecordListState>();
  late String? _status = widget.initialStatus;
  String? _kind;
  bool _open = true;

  Future<void> _new() => newProductionOrder(context, widget.session, onSaved: () => _list.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      key: _list,
      filtersActive: _open || _status != null || _kind != null,
      onClearFilters: () => setState(() {
        _open = false;
        _status = null;
        _kind = null;
      }),
      api: widget.session.api,
      path: '/api/production/orders',
      query: {'status': _status, 'kind': _kind, 'open': _open && _status == null ? true : null},
      searchHint: 'Referência ou produto',
      filters: [
        ChoiceFilter(label: 'Situação', value: _status, choices: productionStatuses, onChanged: (v) => setState(() => _status = v)),
        ChoiceFilter(label: 'Tipo', value: _kind, choices: productionKinds, onChanged: (v) => setState(() => _kind = v)),
        FilterChip(label: const Text('Somente abertas'), selected: _open, onSelected: (v) => setState(() => _open = v)),
      ],
      fab: widget.session.canProduce
          ? FloatingActionButton.extended(heroTag: 'new-of', onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nova Ordem de Fabricação'))
          : null,
      columns: [
        col('Referência', 'reference'),
        col('Produto', 'productCode'),
        col('Descrição', 'productName'),
        col('Quantidade', 'quantity', numeric: true),
        dateCol('Entrega', 'dueDate'),
        ColumnSpec('Início prog.', (e) => fmtDay(e['adjustedStart'] ?? e['plannedStart'])),
        ColumnSpec('Fim prog.', (e) => fmtDay(e['adjustedEnd'] ?? e['plannedEnd'])),
        labelCol('Situação', 'status', productionStatuses),
        col('Cliente', 'customerName'),
      ],
      rowColor: (_, e) => productionLate(e) ? cs.errorContainer : null,
      onTap: (e) => openProductionOrder(context, widget.session, e['id'] as int),
    );
  }
}

/// Production order detail: operations, materials, shop-floor reporting and process editing before release.
class ProductionOrderScreen extends StatefulWidget {
  const ProductionOrderScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<ProductionOrderScreen> createState() => _ProductionOrderScreenState();
}

class _ProductionOrderScreenState extends State<ProductionOrderScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  Map<String, dynamic>? _o;
  String? _error;
  int _version = 0;
  bool _releasing = false;
  Future<dynamic>? _docs;
  Future<dynamic>? _rec;

  Future<dynamic> get docs => _docs ??= api.get('$base/stock-documents');
  Future<dynamic> get rec => _rec ??= api.get('$base/reconciliation');

  ApiClient get api => widget.session.api;
  Session get s => widget.session;
  String get base => '/api/production/orders/${widget.id}';
  String get status => '${_o?['status']}';
  bool get open => openProductionStatuses.contains(status);
  bool get running => runningProductionStatuses.contains(status);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await api.get(base) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _o = o;
          _error = null;
          _bump();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _bump() {
    _version++;
    _docs = null;
    _rec = null;
  }

  void _set(Object? r) {
    if (r is Map<String, dynamic> && r['reference'] != null) {
      setState(() {
        _o = r;
        _bump();
      });
    } else {
      _load();
    }
  }

  Future<void> _post(String action, {Object body = const {}, String? success}) async {
    final r = await runAction(context, () => api.post('$base/$action', body), success: success);
    if (r != null) _set(r);
  }

  Future<void> _release() async {
    // A second tap before the first answer would release twice.
    if (_releasing) return;
    _releasing = true;
    try {
      final go = await confirmStep(
        context,
        title: 'Liberar ${_o!['reference']}?',
        message: 'O material do roteiro é reservado e a OF entra na fila da produção. Se faltar material, você decide se libera mesmo assim.',
        confirmLabel: 'Liberar',
        icon: Icons.play_arrow,
      );
      if (go && mounted) await _releaseNow();
    } finally {
      _releasing = false;
    }
  }

  Future<void> _releaseNow() async {
    try {
      final r = await api.post('$base/release', {'force': false}) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OF liberada e material reservado')));
      _set(r['order']);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status != 409 || !e.message.contains('Missing material')) return showError(context, describeError(e));
      final availability = await api.get('$base/availability') as Map<String, dynamic>;
      if (!mounted) return;
      final short = (availability['lines'] as List).cast<Map<String, dynamic>>().where((l) => (l['shortage'] as num) > 0).toList();
      final force = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Falta material'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SimpleTable(
                columns: [
                  col('Item', 'code'),
                  col('Descrição', 'description'),
                  ColumnSpec('Necessário', (e) => '${fmt(e['remaining'])} ${e['unit']}', numeric: true),
                  col('Livre', 'free', numeric: true),
                  col('Em pedido', 'onOrder', numeric: true),
                  col('Falta', 'shortage', numeric: true),
                ],
                rows: short,
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(key: const ValueKey('release-force'), onPressed: () => Navigator.pop(c, true), child: const Text('Liberar mesmo assim')),
          ],
        ),
      );
      if (force != true || !mounted) return;
      final r = await runAction(context, () => api.post('$base/release', {'force': true}), success: 'OF liberada com reserva parcial');
      if (r is Map<String, dynamic>) _set(r['order']);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> _reason(String action, String title, {bool technical = false}) async {
    final reason = await promptText(context, title: title, label: 'Motivo', required: true);
    if (reason == null || !mounted) return;
    await _post(action, body: {'reason': reason, 'technical': technical});
  }

  /// Cancel with the reason and, as an option, the technical kind: the OF is dropped for a planning reason and is not counted as a loss.
  Future<void> _cancel() async {
    final r = await showDialog<({String reason, bool technical})>(
      context: context,
      builder: (_) => CancelOrderDialog(reference: '${_o!['reference']}'),
    );
    if (r == null || !mounted) return;
    await _post('cancel', body: {'reason': r.reason, 'technical': r.technical}, success: 'OF cancelada');
  }

  /// Finishing with quantity still to be made or waiting in process says so before it is done.
  Future<void> _finish() async {
    final o = _o!;
    final open = (o['operations'] as List).cast<Map<String, dynamic>>().fold<num>(0, (a, op) => a + ((op['remaining'] as num?) ?? 0));
    final wip = (o['workInProcess'] as num?) ?? 0;
    final notes = [if (open > 0) 'Ainda há ${fmt(open)} peça(s) de saldo nas operações.', if (wip > 0) 'Há ${fmt(wip)} em processo.'];
    final go = await confirmStep(
      context,
      title: 'Finalizar ${o['reference']}?',
      message: [...notes, 'Depois de finalizada, a OF não recebe mais apontamentos. Dá para reabri-la enquanto não for encerrada.'].join('\n'),
      confirmLabel: 'Finalizar',
      icon: Icons.flag_outlined,
    );
    if (go && mounted) await _post('finish', success: 'OF finalizada');
  }

  Future<void> _closeOrder() async {
    final go = await confirmStep(
      context,
      title: 'Encerrar ${_o!['reference']}?',
      message: 'A OF sai das listas de abertas e passa a aguardar o fechamento de custo. Não recebe mais entradas nem apontamentos.',
      confirmLabel: 'Encerrar',
      icon: Icons.lock_outline,
    );
    if (go && mounted) await _post('close', success: 'OF encerrada');
  }

  Future<void> _closeCost() async {
    final go = await confirmStep(
      context,
      title: 'Fechar o custo de ${_o!['reference']}?',
      message: 'O custo de material e de serviço de terceiros é gravado como definitivo para esta OF.',
      confirmLabel: 'Fechar custo',
      icon: Icons.calculate_outlined,
      danger: true,
    );
    if (go && mounted) await _post('close-cost', success: 'Custo fechado');
  }

  Future<void> _edit() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Editar ${_o!['reference']}',
      fields: productionUpdateFields,
      initial: _o,
      submit: (b) => api.put(base, b),
    );
    if (r != null) _set(r);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Excluir ${_o!['reference']}?') || !mounted) return;
    final ok = await runAction(context, () async {
      await api.delete(base);
      return true;
    }, success: 'OF excluída');
    if (ok == true && mounted) Navigator.pop(context);
  }

  Future<void> _children() async {
    final go = await confirmStep(
      context,
      title: 'Gerar OFs de subconjuntos?',
      message: 'Cria uma OF para cada subconjunto da estrutura de ${_o!['reference']} que ainda não tem uma.',
      confirmLabel: 'Gerar',
      icon: Icons.account_tree_outlined,
    );
    if (!go || !mounted) return;
    final r = await runAction(context, () => api.post('$base/child-orders', {}));
    if (r is List && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.isEmpty ? 'Nenhuma OF filha necessária' : '${r.length} OF(s) filha(s) gerada(s)')));
      await _load();
      // The new orders are listed on the summary, where the user would look for them.
      if (r.isNotEmpty && mounted) _tabs.animateTo(0);
    }
  }

  Future<void> _schedule() async {
    final r = await runAction(context, () => api.post('$base/schedule', {}));
    if (r is! List || !mounted) return;
    await showScheduleResult(context, r.cast<Map<String, dynamic>>(), session: s);
    unawaited(_load());
  }

  Future<void> _receive() async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Entrada de produto acabado · ${_o!['reference']}',
      fields: [
        FieldSpec('date', 'Data', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true, defaultValue: _o!['receivable']),
        const FieldSpec('locationId', 'Local', type: FieldType.lookup, lookup: LookupSpec('/api/stock-locations'), hint: 'Vazio = parâmetro do PCP'),
        const FieldSpec('lotCode', 'Lote', hint: 'Vazio = referência da OF'),
      ],
      submit: (b) => api.post('$base/receipts', b),
    );
    if (r == null) return;
    unawaited(_load());
    final doc = r['id'];
    if (mounted && doc is int) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Entrada de produto acabado lançada'),
          persist: false, // a snackbar with an action would otherwise stay until dismissed and hold back the next message
          action: SnackBarAction(label: 'Abrir movimentação', onPressed: () => unawaited(openStockDocument(context, s, doc))),
        ),
      );
    }
  }

  List<Widget> _actions() {
    if (_o == null) return [];
    final menu = <PopupMenuEntry<VoidCallback>>[
      if (s.canProduce && open) PopupMenuItem(value: _edit, child: const Text('Editar')),
      if (s.canProduce && status == 'Created')
        PopupMenuItem(
          value: () => _post('refresh-structure', success: 'Estrutura atualizada'),
          child: const Text('Atualizar estrutura'),
        ),
      if (s.canProduce && open) PopupMenuItem(value: _children, child: const Text('Gerar OFs de subconjuntos')),
      if (s.canProduce && open) PopupMenuItem(value: _schedule, child: const Text('Programar')),
      if (s.canProduce && running) PopupMenuItem(value: () => _reason('stop', 'Parar ${_o!['reference']}'), child: const Text('Parar')),
      if (s.canProduce && running) PopupMenuItem(value: _finish, child: const Text('Finalizar')),
      if (s.canProduce && status == 'Finished')
        PopupMenuItem(
          value: () => _post('reopen', success: 'OF reaberta'),
          child: const Text('Reabrir'),
        ),
      if (s.canProduce && status == 'Finished') PopupMenuItem(value: _closeOrder, child: const Text('Encerrar')),
      if (s.canProduce && status == 'Closed' && _o!['costClosedAt'] == null) PopupMenuItem(value: _closeCost, child: const Text('Fechar custo')),
      if (s.canProduce && open) PopupMenuItem(value: _cancel, child: const Text('Cancelar')),
      if (s.canProduce && status == 'Created') PopupMenuItem(value: _delete, child: const Text('Excluir')),
    ];
    return [
      if (_o != null) PrintButton(name: 'Ordem de fabricação ${_o!['reference']}', builder: () => buildProductionOrderPdf(s.api, _o!)),
      if (s.canProduce && status == 'Created')
        TextButton.icon(key: const ValueKey('of-release'), onPressed: _release, icon: const Icon(Icons.play_arrow), label: const Text('Liberar')),
      if (s.canProduce && status == 'Stopped')
        TextButton.icon(
          onPressed: () => _post('resume', success: 'OF retomada'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Retomar'),
        ),
      if (s.canMoveProduction && running)
        Tooltip(
          message: 'Entrada de produto acabado no estoque',
          child: TextButton.icon(
            key: const ValueKey('of-receive'),
            onPressed: _receive,
            icon: const Icon(Icons.move_to_inbox),
            label: const Text('Entrada PA'),
          ),
        ),
      if (menu.isNotEmpty) PopupMenuButton<VoidCallback>(key: const ValueKey('of-menu'), onSelected: (f) => f(), itemBuilder: (_) => menu),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? 'Ordem de fabricação' : '${o['reference']} · ${o['productCode']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (o != null) RelatedMenu(links: _relatedLinks(o)),
          ..._actions(),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Resumo'),
            Tab(text: 'Operações'),
            Tab(text: 'Materiais'),
            Tab(text: 'Apontamentos'),
            Tab(text: 'Beneficiamento'),
            Tab(text: 'Custo'),
          ],
        ),
      ),
      body: _error != null && o == null
          ? LoadError(message: _error!, onRetry: _load)
          : o == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _summary(o),
                _operations(o),
                _materials(o),
                ReportsView(key: ValueKey('rep-$_version'), session: s, order: o, onChanged: _load),
                ShipmentsView(key: ValueKey('ship-$_version'), session: s, orderId: widget.id, onChanged: _load),
                _cost(o),
              ],
            ),
    );
  }

  /// The records this OF points to: product, customer, the sales order it was made for, parent, previous and child OFs, and the suppliers of outside operations.
  List<RelatedLink> _relatedLinks(Map<String, dynamic> o) {
    final children = (o['children'] as List).cast<Map<String, dynamic>>();
    final suppliers = {
      for (final op in (o['operations'] as List).cast<Map<String, dynamic>>())
        if (op['external'] == true && op['supplierId'] is int) op['supplierId'] as int: op['sequence'],
    };
    return [
      RelatedLink(Icons.inventory_2_outlined, 'Produto: ${o['productCode']}', () => openProduct(context, s, o['productId'] as int)),
      if (o['customerId'] is int) RelatedLink(Icons.business_outlined, 'Cliente', () => openCustomer(context, s, o['customerId'] as int)),
      if (o['salesOrderId'] is int)
        RelatedLink(
          Icons.receipt_long_outlined,
          'Pedido de venda ${o['salesOrderReference'] ?? ''}',
          () => openSalesOrder(context, s, o['salesOrderId'] as int),
        ),
      if (o['parentOrderId'] is int)
        RelatedLink(Icons.north, 'OF pai ${o['parentOrderReference'] ?? ''}', () => openProductionOrder(context, s, o['parentOrderId'] as int)),
      if (o['previousOrderId'] is int)
        RelatedLink(Icons.undo, 'OF anterior ${o['previousOrderReference'] ?? ''}', () => openProductionOrder(context, s, o['previousOrderId'] as int)),
      for (final c in children)
        RelatedLink(Icons.subdirectory_arrow_right, 'OF filha ${c['reference']}', () => openProductionOrder(context, s, c['id'] as int)),
      for (final e in suppliers.entries) RelatedLink(Icons.local_shipping_outlined, 'Fornecedor da operação ${e.value}', () => openSupplier(context, s, e.key)),
    ];
  }

  Widget _summary(Map<String, dynamic> o) {
    final cs = Theme.of(context).colorScheme;
    final warnings = (o['warnings'] as List).cast<String>();
    final children = (o['children'] as List).cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (['Stopped', 'Cancelled'].contains(o['status']) && o['statusReason'] != null)
          Card(
            key: const ValueKey('of-status-reason'),
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(o['status'] == 'Stopped' ? Icons.pause_circle_outline : Icons.block, color: cs.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${productionStatuses[o['status']] ?? o['status']}: ${o['statusReason']}', style: TextStyle(color: cs.onErrorContainer)),
                  ),
                ],
              ),
            ),
          ),
        if (warnings.isNotEmpty)
          Card(
            color: cs.errorContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(warnings.join('\n'))),
          ),
        Section(
          title: 'Ordem',
          child: InfoGrid([
            ('Situação', '${productionStatuses[o['status']] ?? o['status']}${o['statusReason'] == null ? '' : ' · ${o['statusReason']}'}'),
            ('Tipo', productionKinds[o['kind']] ?? fmt(o['kind'])),
            ('Pedido de venda', fmt(o['salesOrderReference'])),
            ('Pedido do cliente', fmt(o['customerPo'])),
            ('OF anterior', fmt(o['previousOrderReference'])),
            ('Produto', '${o['productCode']} · ${o['productName']}'),
            ('Quantidade', '${fmt(o['quantity'])} ${o['productUnit']}'),
            ('Entrega', fmtDay(o['dueDate'])),
            ('Programado', o['plannedStart'] == null ? '' : '${fmtDay(o['plannedStart'])} a ${fmtDay(o['plannedEnd'])}'),
            ('Ajustado', o['adjustedStart'] == null ? '' : '${fmtDay(o['adjustedStart'])} a ${fmtDay(o['adjustedEnd'])}'),
            ('Amarrados', fmt(o['bales'])),
            ('Tubo primário', fmt(o['primaryTube'])),
            ('Observações', fmt(o['notes'])),
            ('Criada', '${fmt(o['createdBy'])} · ${fmtDate(o['createdAt'])}'),
            ('Liberada', fmtDate(o['releasedAt'])),
            ('Finalizada', fmtDate(o['finishedAt'])),
            ('Encerrada', o['closedAt'] == null ? '' : '${fmt(o['closedBy'])} · ${fmtDate(o['closedAt'])}'),
          ]),
        ),
        const SizedBox(height: 12),
        Section(
          title: 'Andamento',
          child: InfoGrid([
            ('Boas', fmt(o['good'])),
            ('Refugo', fmt(o['scrap'])),
            ('Recebido no estoque', fmt(o['received'])),
            ('A receber', fmt(o['receivable'])),
            ('Em processo', fmt(o['workInProcess'])),
          ]),
        ),
        if (o['parentOrderId'] != null || o['previousOrderId'] != null || children.isNotEmpty) ...[
          const SizedBox(height: 12),
          Section(
            title: 'Subconjuntos',
            actions: [
              if (o['previousOrderId'] != null)
                TextButton.icon(
                  onPressed: () => openProductionOrder(context, s, o['previousOrderId'] as int).then((_) => _load()),
                  icon: const Icon(Icons.undo),
                  label: Text('OF anterior ${o['previousOrderReference'] ?? ''}'.trim()),
                ),
              if (o['parentOrderId'] != null)
                TextButton.icon(
                  onPressed: () => openProductionOrder(context, s, o['parentOrderId'] as int).then((_) => _load()),
                  icon: const Icon(Icons.north),
                  label: Text('OF pai ${o['parentOrderReference'] ?? ''}'.trim()),
                ),
            ],
            child: SimpleTable(
              columns: [
                col('Referência', 'reference'),
                col('Produto', 'productCode'),
                col('Quantidade', 'quantity', numeric: true),
                dateCol('Entrega', 'dueDate'),
                labelCol('Situação', 'status', productionStatuses),
              ],
              rows: children,
              actions: (c) => [
                IconButton(
                  tooltip: 'Abrir',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => openProductionOrder(context, s, c['id'] as int).then((_) => _load()),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _report(Map<String, dynamic> op) async {
    final r = await showReportForm(context, s, _o!, op);
    if (r != null) unawaited(_load());
  }

  Future<void> _details(Map<String, dynamic> op) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Tolerância e medidas · operação ${op['sequence']}',
      fields: const [
        FieldSpec('tolerance', 'Requisitos/Tolerância', hint: 'Ex.: ± 0,10'),
        FieldSpec('measureStart', 'Medida início'),
        FieldSpec('measureEnd', 'Medida final'),
      ],
      initial: {'tolerance': op['tolerance'], 'measureStart': op['measureStart'], 'measureEnd': op['measureEnd']},
      submit: (b) => api.put('$base/operations/${op['sequence']}/details', b),
    );
    if (r != null) _set(r);
  }

  Future<void> _editProcess(List<Map<String, dynamic>> ops) async {
    final lines = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ProcessDialog(ops: ops),
    );
    if (lines == null || !mounted) return;
    final r = await runAction(context, () => api.put('$base/process', {'operations': lines}), success: 'Processo salvo');
    if (r != null) _set(r);
  }

  Future<void> _outsource(Map<String, dynamic> op) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Beneficiamento externo · operação ${op['sequence']}',
      fields: const [
        FieldSpec('supplierId', 'Fornecedor', type: FieldType.lookup, required: true, lookup: supplierLookup),
        FieldSpec('leadDays', 'Prazo (dias)', type: FieldType.integer),
      ],
      initial: op['supplierId'] == null ? null : {'supplierId': op['supplierId'], 'leadDays': op['externalLeadDays']},
      submit: (b) => api.put('$base/operations/${op['sequence']}/outsource', b),
    );
    if (r != null) _set(r);
  }

  Future<void> _internal(Map<String, dynamic> op) async {
    if (!await confirm(context, 'Voltar a operação ${op['sequence']} para produção interna?') || !mounted) return;
    final r = await runAction(context, () => api.delete('$base/operations/${op['sequence']}/outsource'));
    _set(r);
  }

  Future<void> _overrun(Map<String, dynamic> op) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Liberar excedente · operação ${op['sequence']}',
      fields: const [
        FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true),
        FieldSpec('justification', 'Justificativa', required: true),
      ],
      submit: (b) => api.post('$base/operations/${op['sequence']}/overrun-releases', b),
    );
    if (r != null) unawaited(_load());
  }

  Future<void> _send(Map<String, dynamic> op) async {
    final r = await submitForm(
      context,
      api: api,
      title: 'Remessa para beneficiamento · operação ${op['sequence']}',
      fields: [
        FieldSpec('date', 'Data', type: FieldType.date, required: true, defaultValue: isoDate(DateTime.now())),
        FieldSpec('quantity', 'Quantidade', type: FieldType.decimal, required: true, defaultValue: op['remaining']),
        const FieldSpec('unitValue', 'Valor de referência (R\$/un.)', type: FieldType.decimal, hint: 'Obrigatório para emitir a NF 5901 automaticamente'),
        const FieldSpec('invoiceNumber', 'NF de remessa', hint: 'Vazio = emitir NF-e (quando o emissor estiver ligado)'),
        const FieldSpec('notes', 'Observações'),
      ],
      submit: (b) => api.post('$base/operations/${op['sequence']}/outside-shipments', b),
    );
    if (r != null) {
      unawaited(_load());
      if (mounted) {
        await printNf(
          context,
          name: 'NF remessa ${r['reference']}',
          number: r['invoiceNumber'] == null ? '' : '${r['invoiceNumber']}',
          build: (f) => buildOutsideNfPdf(api, r, f),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remessa ${r['reference']} registrada'),
            persist: false,
            action: SnackBarAction(label: 'Ver remessas', onPressed: () => _tabs.animateTo(4)),
          ),
        );
      }
    }
  }

  Widget _operations(Map<String, dynamic> o) {
    final ops = (o['operations'] as List).cast<Map<String, dynamic>>();
    final reportable = runningProductionStatuses.contains(o['status']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Roteiro',
          actions: [
            if (o['status'] == 'Created' && s.canProduce)
              TextButton.icon(
                key: const ValueKey('op-edit-process'),
                onPressed: () => _editProcess(ops),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar processo'),
              ),
          ],
          child: SimpleTable(
            columns: [
              col('Seq.', 'sequence'),
              ColumnSpec('Descrição', (e) => '${e['description'] ?? ''}${e['external'] == true ? ' (externo)' : ''}'),
              col('Máquina', 'machineCode'),
              col('Tolerância', 'tolerance'),
              ColumnSpec('Medidas', (e) => [e['measureStart'], e['measureEnd']].where((m) => m != null).join(' / ')),
              col('Setup (h)', 'setupHours', numeric: true),
              col('Peças/h', 'piecesPerHour', numeric: true),
              ColumnSpec('Horas', (e) => fmtNum(e['plannedHours']), numeric: true),
              ColumnSpec('Programado', (e) => e['plannedStart'] == null ? '' : '${fmtDay(e['plannedStart'])} a ${fmtDay(e['plannedEnd'])}'),
              col('Boas', 'good', numeric: true),
              col('Refugo', 'scrap', numeric: true),
              col('Em beneficiamento', 'inTransit', numeric: true),
              col('Limite', 'limit', numeric: true),
              col('Saldo', 'remaining', numeric: true),
            ],
            rows: ops,
            actionsFirst: true,
            actions: open && (s.canProduce || s.canMoveProduction)
                ? (op) => [
                    // A user who can move material but not report sees why the button does nothing.
                    if (reportable && !s.canProduce)
                      IconButton(
                        key: ValueKey('op-report-${op['sequence']}'),
                        tooltip: 'Sem permissão para apontar',
                        icon: const Icon(Icons.edit_note, size: 20),
                        onPressed: null,
                      ),
                    if (s.canProduce && reportable && op['external'] != true)
                      IconButton(
                        key: ValueKey('op-report-${op['sequence']}'),
                        tooltip: 'Apontar',
                        icon: const Icon(Icons.edit_note, size: 20),
                        onPressed: () => _report(op),
                      ),
                    if (s.canProduce && reportable && op['external'] == true)
                      IconButton(
                        key: ValueKey('op-send-${op['sequence']}'),
                        tooltip: 'Enviar ao beneficiamento',
                        icon: const Icon(Icons.local_shipping_outlined, size: 20),
                        onPressed: () => _send(op),
                      ),
                    if (s.canProduce)
                      PopupMenuButton<VoidCallback>(
                        key: ValueKey('op-menu-${op['sequence']}'),
                        onSelected: (f) => f(),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: () => _outsource(op), child: Text(op['external'] == true ? 'Trocar fornecedor' : 'Beneficiamento externo')),
                          if (op['external'] == true) PopupMenuItem(value: () => _internal(op), child: const Text('Voltar para interno')),
                          PopupMenuItem(value: () => _overrun(op), child: const Text('Liberar excedente')),
                          PopupMenuItem(value: () => _details(op), child: const Text('Tolerância e medidas')),
                        ],
                      ),
                  ]
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _issue([Map<String, dynamic>? line]) async {
    final today = isoDate(DateTime.now());
    if (line == null) {
      if (!await confirm(context, 'Requisitar todo o saldo dos materiais para ${_o!['reference']}?') || !mounted) return;
      final r = await runAction(context, () => api.post('$base/issues', {'date': today}), success: 'Material requisitado');
      if (r != null) unawaited(_load());
      return;
    }
    final r = await submitForm(
      context,
      api: api,
      title: line['material'] == true ? 'Requisitar ${line['code']}' : 'Devolver ${line['code']}',
      fields: [
        FieldSpec('date', 'Data', type: FieldType.date, required: true, defaultValue: today),
        FieldSpec(
          'quantity',
          'Quantidade (${line['unit']})',
          type: FieldType.decimal,
          required: true,
          defaultValue: line['material'] == true ? line['remaining'] : null,
        ),
        FieldSpec(
          'lotId',
          'Lote',
          type: FieldType.lookup,
          lookup: LookupSpec(
            '/api/stock/lots',
            query: {'materialId': line['materialId'], 'productId': line['componentProductId'], if (line['material'] == true) 'status': 'Released'},
          ),
        ),
        const FieldSpec('locationId', 'Local', type: FieldType.lookup, lookup: LookupSpec('/api/stock-locations'), hint: 'Vazio = parâmetro do PCP'),
      ],
      submit: (b) => api.post(line['material'] == true ? '$base/issues' : '$base/material-returns', {
        'date': b['date'],
        'locationId': b['locationId'],
        'lines': [
          {'materialLineId': line['id'], 'quantity': b['quantity'], 'lotId': b['lotId']},
        ],
      }),
    );
    if (r != null) unawaited(_load());
  }

  /// Stock documents (issues and returns) of this order.
  Widget _stockMovements() => Section(
    title: 'Movimentações de estoque',
    child: FutureView<dynamic>(
      key: ValueKey('docs-$_version'),
      future: docs,
      builder: (context, docs) => SimpleTable(
        columns: [
          col('Nº', 'id'),
          labelCol('Tipo', 'type', movementTypes),
          dateCol('Data', 'date'),
          col('Linhas', 'movementCount', numeric: true),
          col('Usuário', 'createdBy'),
          ColumnSpec('Estornado', (e) => e['reversed'] == true ? 'Sim' : ''),
        ],
        rows: (docs as List).cast<Map<String, dynamic>>(),
        actions: (d) => [
          IconButton(
            tooltip: 'Abrir',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => openStockDocument(context, s, d['id'] as int).then((_) => _load()),
          ),
        ],
      ),
    ),
  );

  Widget _materials(Map<String, dynamic> o) {
    final lines = (o['materials'] as List).cast<Map<String, dynamic>>();
    final canIssue = s.canMoveProduction && running;
    final canReturn = s.canMoveProduction && o['status'] != 'Closed' && o['status'] != 'Created';
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Materiais e reservas',
          actions: [
            if (canIssue && lines.any((l) => (l['remaining'] as num) > 0))
              FilledButton.tonalIcon(
                key: const ValueKey('issue-all'),
                onPressed: _issue,
                icon: const Icon(Icons.outbox_outlined),
                label: const Text('Requisitar saldo'),
              ),
          ],
          child: SimpleTable(
            columns: [
              col('Op.', 'operationSequence'),
              col('Item', 'code'),
              col('Descrição', 'description'),
              col('Por peça', 'quantityPerUnit', numeric: true),
              ColumnSpec('Necessário', (e) => '${fmt(e['required'])} ${e['unit']}', numeric: true),
              col('Reservado', 'reserved', numeric: true),
              col('Requisitado', 'issued', numeric: true),
              col('Saldo', 'remaining', numeric: true),
            ],
            rows: lines,
            actionsFirst: true,
            rowColor: (e) => (e['remaining'] as num) > 0 && (e['reserved'] as num) < (e['remaining'] as num) && open ? cs.tertiaryContainer : null,
            actions: canIssue || canReturn
                ? (l) => [
                    if (canIssue)
                      IconButton(
                        key: ValueKey('issue-${l['id']}'),
                        tooltip: 'Requisitar',
                        icon: const Icon(Icons.outbox_outlined, size: 20),
                        onPressed: (l['remaining'] as num) > 0 ? () => _issue({...l, 'material': true}) : null,
                      ),
                    if (canReturn)
                      IconButton(
                        tooltip: 'Devolver ao estoque',
                        icon: const Icon(Icons.undo, size: 20),
                        onPressed: (l['issued'] as num) > 0 ? () => _issue({...l, 'material': false}) : null,
                      ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _stockMovements(),
      ],
    );
  }

  Widget _cost(Map<String, dynamic> o) => FutureView<dynamic>(
    key: ValueKey('cost-$_version'),
    future: rec,
    builder: (context, r) {
      final rec = r as Map<String, dynamic>;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Section(
            title: o['costClosedAt'] == null ? 'Custo (prévia)' : 'Custo fechado em ${fmtDate(o['costClosedAt'])}',
            child: InfoGrid([
              ('Planejado', fmt(rec['planned'])),
              ('Boas', fmt(rec['good'])),
              ('Refugo', fmt(rec['scrap'])),
              ('Recebido', fmt(rec['received'])),
              ('Em processo', fmt(rec['workInProcess'])),
              ('Material', fmtMoney(o['materialCost'] ?? rec['materialCost'])),
              ('Serviço de terceiros', fmtMoney(o['serviceCost'] ?? rec['serviceCost'])),
              ('Custo unitário', fmtMoney(o['unitCost'] ?? rec['unitCost'])),
            ]),
          ),
          const SizedBox(height: 12),
          Section(
            title: 'Balanço de material',
            child: SimpleTable(
              columns: [
                col('Item', 'code'),
                col('Un.', 'unit'),
                col('Planejado', 'planned', numeric: true),
                col('Requisitado', 'issued', numeric: true),
                col('No refugo', 'inScrap', numeric: true),
                col('No acabado', 'inFinishedGoods', numeric: true),
                col('Saldo', 'balance', numeric: true),
                ColumnSpec('Preço', (e) => fmtNum(e['unitPrice'], 4), numeric: true),
                moneyCol('Valor saldo', 'balanceValue'),
              ],
              rows: (rec['lines'] as List).cast<Map<String, dynamic>>(),
            ),
          ),
        ],
      );
    },
  );
}

/// Edits the process written on the OF paper: one row per operation (description, requirements, start and final measures).
class _ProcessDialog extends StatefulWidget {
  const _ProcessDialog({required this.ops});

  final List<Map<String, dynamic>> ops;

  @override
  State<_ProcessDialog> createState() => _ProcessDialogState();
}

class _ProcessRow {
  _ProcessRow(Map<String, dynamic>? op)
    : sequence = op?['sequence'] as int?,
      description = TextEditingController(text: '${op?['description'] ?? ''}'),
      tolerance = TextEditingController(text: '${op?['tolerance'] ?? ''}'),
      start = TextEditingController(text: '${op?['measureStart'] ?? ''}'),
      end = TextEditingController(text: '${op?['measureEnd'] ?? ''}');

  final int? sequence;
  final TextEditingController description, tolerance, start, end;

  void dispose() {
    for (final c in [description, tolerance, start, end]) {
      c.dispose();
    }
  }
}

class _ProcessDialogState extends State<_ProcessDialog> {
  late final List<_ProcessRow> _rows = [for (final op in widget.ops) _ProcessRow(op)];
  String _initial = '';

  /// What the dialog holds, to tell whether leaving would lose an edit.
  String _signature() => [for (final r in _rows) '${r.sequence}|${r.description.text}|${r.tolerance.text}|${r.start.text}|${r.end.text}'].join('\n');

  bool get _dirty => _signature() != _initial;

  @override
  void initState() {
    super.initState();
    _initial = _signature();
  }

  void _move(int i, int delta) => setState(() {
    final r = _rows.removeAt(i);
    _rows.insert(i + delta, r);
  });

  Future<void> _cancel() async {
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {Key? key}) => TextField(
    key: key,
    controller: c,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(labelText: label, isDense: true),
  );

  @override
  Widget build(BuildContext context) {
    final valid = _rows.isNotEmpty && _rows.every((r) => r.description.text.trim().isNotEmpty);
    return AlertDialog(
      title: const Text('Processo da ordem de produção'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tudo o que o produto passa, na ordem. Isto é o que sai impresso no meio da ordem de fabricação.'),
              const SizedBox(height: 12),
              for (final (i, r) in _rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The server renumbers 10, 20, 30... by position, so this is the number the operation will have.
                      Padding(padding: const EdgeInsets.only(top: 12, right: 8), child: Text('${(i + 1) * 10}')),
                      Expanded(flex: 4, child: _field(r.description, 'Descrição da operação', key: ValueKey('process-desc-$i'))),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _field(r.tolerance, 'Requisitos/Tolerância')),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _field(r.start, 'Início')),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _field(r.end, 'Final')),
                      IconButton(
                        key: ValueKey('process-up-$i'),
                        tooltip: 'Subir',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0 ? null : () => _move(i, -1),
                      ),
                      IconButton(
                        key: ValueKey('process-down-$i'),
                        tooltip: 'Descer',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: i == _rows.length - 1 ? null : () => _move(i, 1),
                      ),
                      IconButton(
                        key: ValueKey('process-del-$i'),
                        tooltip: r.sequence != null ? 'Operação do roteiro da OF: não pode ser removida aqui' : 'Remover',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: r.sequence != null ? null : () => setState(() => _rows.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                key: const ValueKey('process-add'),
                onPressed: () => setState(() => _rows.add(_ProcessRow(null))),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar operação'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('process-cancel'), onPressed: _cancel, child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('process-save'),
          onPressed: !valid
              ? null
              : () => Navigator.pop(context, [
                  for (final r in _rows)
                    {
                      'sequence': r.sequence,
                      'description': r.description.text,
                      'tolerance': r.tolerance.text,
                      'measureStart': r.start.text,
                      'measureEnd': r.end.text,
                    },
                ]),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
