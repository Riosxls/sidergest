import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/pipeline.dart' show StatusBadge, Tone;
import '../widgets/record_list.dart';
import '../widgets/record_nav.dart';
import 'product_detail.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';
import 'where_used.dart';

/// Opens the stock page of one item (a material or a product) as a record page. [title] is the item's code and description when the caller has them.
Future<void> openItemStock(BuildContext context, Session session, {int? materialId, int? productId, String? title}) {
  final material = materialId != null;
  final id = (materialId ?? productId)!;
  // The list offered its balance row ids, which are not item ids: drop them so the page does not step through unrelated records.
  RecordSiblings.take(-1);
  return pushRecord<void>(context, material ? 'material-stock' : 'product-stock', id, (_) => itemStockScreen(session, material: material, id: id, title: title));
}

/// The stock page of an item; without a [title] it loads the item first (a web address, a restored place).
Widget itemStockScreen(Session session, {required bool material, required int id, String? title}) {
  ItemStockScreen page(String t) => ItemStockScreen(session: session, materialId: material ? id : null, productId: material ? null : id, title: t);
  if (title != null) return page(title);
  return RecordLoader(
    title: material ? 'Estoque do material' : 'Estoque do produto',
    load: () => session.api.get(material ? '/api/materials/$id' : '/api/products/$id'),
    builder: (d) => page('${d['code']} · ${d['description'] ?? d['name'] ?? ''}'),
  );
}

/// Stock balances.
class BalancesScreen extends StatefulWidget {
  const BalancesScreen({super.key, required this.session});

  final Session session;

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  String? _location;
  bool _includeZero = false;
  Map<String, String> _locations = {};

  @override
  void initState() {
    super.initState();
    widget.session.api.listAll('/api/stock-locations').then((l) {
      if (mounted) setState(() => _locations = {for (final x in l) '${x['id']}': '${x['code']} · ${x['name']}'});
    }, onError: (Object e) => debugPrint('stock_balances: locations lookup failed: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      api: widget.session.api,
      path: '/api/stock/balances',
      query: {'locationId': _location, 'includeZero': _includeZero ? true : null},
      searchHint: 'Código do item',
      filtersActive: _location != null || _includeZero,
      onClearFilters: () => setState(() {
        _location = null;
        _includeZero = false;
      }),
      filters: [
        ChoiceFilter(key: ValueKey(_locations.length), label: 'Local', value: _location, choices: _locations, onChanged: (v) => setState(() => _location = v)),
        FilterChip(label: const Text('Incluir zerados'), selected: _includeZero, onSelected: (v) => setState(() => _includeZero = v)),
      ],
      columns: [
        col('Código', 'itemCode'),
        col('Descrição', 'itemDescription'),
        col('Local', 'locationCode'),
        col('Lote', 'lotCode'),
        labelCol('Situação lote', 'lotStatus', lotStatuses),
        // The red row says it with colour only; the badge says it in words.
        ColumnSpec(
          'Quantidade',
          (e) => fmt(e['quantity']),
          numeric: true,
          cell: (context, e) => (e['quantity'] as num) < 0
              ? Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [const StatusBadge('Negativo', tone: Tone.danger, icon: Icons.warning_amber_rounded), Text(fmt(e['quantity']))],
                )
              : Text(fmt(e['quantity'])),
        ),
      ],
      rowColor: (_, e) => (e['quantity'] as num) < 0 || e['lotStatus'] == 'Rejected'
          ? cs.errorContainer
          : e['lotStatus'] == 'Quarantine' || e['locationKind'] == 'Quarantine'
          ? cs.tertiaryContainer
          : null,
      onTap: (e) => openItemStock(
        context,
        widget.session,
        materialId: e['materialId'] as int?,
        productId: e['productId'] as int?,
        title: '${e['itemCode']} · ${e['itemDescription']}',
      ),
    );
  }
}

/// Stock detail of one item.
class ItemStockScreen extends StatelessWidget {
  const ItemStockScreen({super.key, required this.session, this.materialId, this.productId, required this.title});

  final Session session;
  final int? materialId;
  final int? productId;
  final String title;

  Map<String, dynamic> get item => {'materialId': materialId, 'productId': productId};

  Future<void> _editMaterial(BuildContext context) async {
    final id = materialId!;
    try {
      final m = await session.api.get('/api/materials/$id') as Map<String, dynamic>;
      if (!context.mounted) return;
      await showEntityForm(
        context,
        api: session.api,
        title: 'Material ${m['code']}',
        fields: materials.fields,
        initial: m,
        readOnly: !session.permissions.contains(materials.writePolicy),
        onSubmit: (body) async => await session.api.put('/api/materials/$id', body) as Map<String, dynamic>?,
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = session.api;
    final tabs = ['Disponibilidade', 'Kardex', 'Lotes', 'Reservas', if (materialId != null) 'Compras'];
    final spec = materialId != null ? materials : products;
    final id = (materialId ?? productId)!;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            RelatedMenu(
              links: [
                if (materialId != null) RelatedLink(Icons.inventory_2_outlined, 'Cadastro do material', () => _editMaterial(context)),
                if (productId != null) RelatedLink(Icons.precision_manufacturing_outlined, 'Produto', () => openProduct(context, session, productId!)),
                RelatedLink(
                  Icons.account_tree_outlined,
                  'Onde é usado',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WhereUsedScreen(session: session, path: '${spec.path}/$id/where-used', title: 'Onde é usado: $title'),
                    ),
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t)],
          ),
        ),
        body: TabBarView(
          children: [
            _Availability(session: session, query: item),
            RecordList(
              api: api,
              path: '/api/stock/movements',
              query: item,
              searchable: false,
              columns: [
                dateCol('Data', 'date'),
                labelCol('Tipo', 'type', movementTypes),
                col('Doc.', 'documentId'),
                col('Referência', 'reference'),
                col('Local', 'locationCode'),
                col('Lote', 'lotCode'),
                col('Quantidade', 'quantity', numeric: true),
                col('Saldo', 'balanceAfter', numeric: true),
                ColumnSpec('Custo unit.', (e) => fmtNum(e['unitCost'], 4), numeric: true),
              ],
              onTap: (e) => openStockDocument(context, session, e['documentId'] as int),
            ),
            LotsView(session: session, query: item),
            ReservationsView(session: session, query: item),
            if (materialId != null) _PurchaseHistory(session: session, materialId: materialId!),
          ],
        ),
      ),
    );
  }
}

class _Availability extends StatefulWidget {
  const _Availability({required this.session, required this.query});

  final Session session;
  final Map<String, dynamic> query;

  @override
  State<_Availability> createState() => _AvailabilityState();
}

class _AvailabilityState extends State<_Availability> {
  late Future<dynamic> _future = _fetch();

  Future<dynamic> _fetch() => widget.session.api.get('/api/stock/availability', widget.query);

  @override
  Widget build(BuildContext context) => FutureView<dynamic>(
    future: _future,
    onRetry: () => setState(() => _future = _fetch()),
    builder: (context, a) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Disponibilidade',
          child: InfoGrid([
            ('Em estoque', fmt(a['onHand'])),
            ('Liberado', fmt(a['released'])),
            ('Bloqueado / quarentena', fmt(a['blocked'])),
            ('Em terceiros', fmt(a['atThirdParty'])),
            ('Reservado', fmt(a['reserved'])),
            ('Livre', fmt(a['free'])),
            if (widget.query['materialId'] != null) ('Custo médio', fmtNum(a['averageCost'], 4)),
          ]),
        ),
        const SizedBox(height: 12),
        Section(
          title: 'Por local',
          child: SimpleTable(
            columns: [col('Local', 'locationCode'), labelCol('Tipo', 'kind', locationKinds), col('Quantidade', 'quantity', numeric: true)],
            rows: (a['byLocation'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
      ],
    ),
  );
}

class _PurchaseHistory extends StatefulWidget {
  const _PurchaseHistory({required this.session, required this.materialId});

  final Session session;
  final int materialId;

  @override
  State<_PurchaseHistory> createState() => _PurchaseHistoryState();
}

class _PurchaseHistoryState extends State<_PurchaseHistory> {
  late Future<dynamic> _future = _fetch();

  Future<dynamic> _fetch() => widget.session.api.get('/api/purchasing/materials/${widget.materialId}/history');

  @override
  Widget build(BuildContext context) => FutureView<dynamic>(
    future: _future,
    onRetry: () => setState(() => _future = _fetch()),
    builder: (context, rows) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SimpleTable(
        columns: [
          dateCol('Data NF', 'invoiceDate'),
          col('NF', 'invoiceNumber'),
          col('Fornecedor', 'supplierName'),
          col('Pedido', 'purchaseOrderNumber'),
          col('Quantidade', 'quantity', numeric: true),
          col('Un.', 'unit'),
          ColumnSpec('Preço líquido', (e) => fmtNum(e['netUnitPrice'], 4), numeric: true),
          moneyCol('Total', 'total'),
        ],
        rows: (rows as List).cast<Map<String, dynamic>>(),
      ),
    ),
  );
}
