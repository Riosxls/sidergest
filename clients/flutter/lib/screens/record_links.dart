import 'package:flutter/material.dart';

import '../session.dart';
import '../widgets/record_nav.dart';
import 'certificates.dart';
import 'deliveries.dart';
import 'fiscal.dart';
import 'production_orders.dart';
import 'sales_orders.dart';
import 'sales_quotes.dart';
import 'steel.dart';
import 'viability.dart';

/// Names shown in the breadcrumb for each record kind opened with `pushRecord`.
const recordLabels = {
  'quote': 'Orçamento',
  'sales-order': 'Pedido de venda',
  'delivery': 'Entrega',
  'production-order': 'Ordem de fabricação',
  'certificate': 'Certificado',
  'fiscal': 'Nota fiscal',
  'feasibility': 'Viabilidade',
  'steel-lot': 'Lote de aço',
};

/// The page of a record kind, or null for an unknown kind (an old bookmark, a hand-edited address).
Widget? recordScreen(Session s, String kind, int id) => switch (kind) {
  'quote' => QuoteScreen(session: s, id: id),
  'sales-order' => SalesOrderScreen(session: s, id: id),
  'delivery' => DeliveryScreen(session: s, id: id),
  'production-order' => ProductionOrderScreen(session: s, id: id),
  'certificate' => CertificateScreen(session: s, id: id),
  'fiscal' => FiscalDocumentScreen(session: s, id: id),
  'feasibility' => FeasibilityScreen(session: s, id: id),
  'steel-lot' => SteelLotScreen(session: s, id: id),
  _ => null,
};

/// Opens a record by kind and id. False when the kind is unknown.
bool openRecordByKind(BuildContext context, Session s, String kind, int id) {
  if (recordScreen(s, kind, id) == null) return false;
  pushRecord<void>(context, kind, id, (_) => recordScreen(s, kind, id)!);
  return true;
}

/// Replaces the open record page with a neighbour from the list it was opened from (previous / next record).
void stepRecord(NavigatorState nav, Session s, RecordTop from, int delta) {
  final ids = from.siblings;
  final i = from.index + delta;
  if (ids == null || i < 0 || i >= ids.length) return;
  final id = ids[i];
  final page = recordScreen(s, from.kind, id);
  if (page == null) return;
  nav.pushReplacement(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: recordRouteName(from.kind, id), arguments: ids),
      builder: (_) => page,
    ),
  );
}
