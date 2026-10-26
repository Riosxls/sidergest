import 'package:flutter/material.dart';

import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/record_list.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';

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
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RecordList(
      api: widget.session.api,
      path: '/api/stock/balances',
      query: {'locationId': _location, 'includeZero': _includeZero ? true : null},
      searchHint: 'Código do item',
      filters: [
        ChoiceFilter(key: ValueKey(_locations.length), label: 'Local', value: _location, choices: _locations, onChanged: (v) => setState(() => _location = v)),
        FilterChip(label: const Text('Incluir zerados'), selected: _includeZero, onSelected: (v) => setState(() => _includeZero = v)),
      ],
      columns: [
        col('Código', 'itemCode'),
        col('Descrição', 'itemDescription'),
        col('Local', 'locationCode'),
        labelCol('Tipo local', 'locationKind', locationKinds),
        col('Lote', 'lotCode'),
        labelCol('Situação lote', 'lotStatus', lotStatuses),
        col('Quantidade', 'quantity', numeric: true),
      ],
      rowColor: (_, e) => (e['quantity'] as num) < 0 || e['lotStatus'] == 'Rejected'
          ? cs.errorContainer
          : e['lotStatus'] == 'Quarantine' || e['locationKind'] == 'Quarantine'
          ? cs.tertiaryContainer
          : null,
      onTap: (e) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ItemStockScreen(
            session: widget.session,
            materialId: e['materialId'] as int?,
            productId: e['productId'] as int?,
            title: '${e['itemCode']} · ${e['itemDescription']}',
          ),
        ),
      ),
    );
  }
}

class ItemStockScreen extends StatelessWidget {
  const ItemStockScreen({super.key, required this.session, this.materialId, this.productId, required this.title});

  final Session session;
  final int? materialId;
  final int? productId;
  final String title;

  Map<String, dynamic> get item => {'materialId': materialId, 'productId': productId};

  @override
  Widget build(BuildContext context) {
    final api = session.api;
    final tabs = ['Disponibilidade', 'Kardex', 'Lotes', 'Reservas', if (materialId != null) 'Compras'];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
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
              onTap: (e) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentScreen(session: session, id: e['documentId'] as int),
                ),
              ),
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

class _Availability extends StatelessWidget {
  const _Availability({required this.session, required this.query});

  final Session session;
  final Map<String, dynamic> query;

  @override
  Widget build(BuildContext context) => FutureView<dynamic>(
    future: session.api.get('/api/stock/availability', query),
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
            if (query['materialId'] != null) ('Custo médio', fmtNum(a['averageCost'], 4)),
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

class _PurchaseHistory extends StatelessWidget {
  const _PurchaseHistory({required this.session, required this.materialId});

  final Session session;
  final int materialId;

  @override
  Widget build(BuildContext context) => FutureView<dynamic>(
    future: session.api.get('/api/purchasing/materials/$materialId/history'),
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
