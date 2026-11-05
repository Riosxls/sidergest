import 'package:flutter/material.dart';

import '../entities.dart';
import '../session.dart';
import '../widgets/pipeline.dart' show Tone;
import 'sales_common.dart' show quoteAlertSpecs;

// Pure helpers of the quote screens (pricing, discount, estimate, alerts, file size). No widgets, no API: unit tested in test/quote_pricing_test.dart.

num _n(Object? v) => v is num ? v : 0;

/// "1,5 MB" / "300 KB" for a file size in bytes.
String fmtFileSize(Object? v) {
  final n = v is num ? v : 0;
  return n >= 1048576 ? '${fmtDecimalInput(n / 1048576, 1)} MB' : '${(n / 1024).ceil()} KB';
}

/// Quantity × unit price, plus IPI and ICMS amounts (both on the base value) when set.
num lineEstimate(Map<String, dynamic> l) {
  final base = _n(l['quantity']) * _n(l['unitPrice']);
  return base + base * _n(l['ipiPercent']) / 100 + base * _n(l['icmsPercent']) / 100;
}

/// Products, IPI and ICMS of the lines that already have a price. The API total is products + IPI; the estimate adds ICMS on top.
({num products, num ipi, num icms}) estimateParts(Iterable<Map<String, dynamic>> lines) {
  num products = 0, ipi = 0, icms = 0;
  for (final l in lines) {
    final base = _n(l['quantity']) * _n(l['unitPrice']);
    products += base;
    ipi += base * _n(l['ipiPercent']) / 100;
    icms += base * _n(l['icmsPercent']) / 100;
  }
  return (products: products, ipi: ipi, icms: icms);
}

/// Discount (percent) of [price] against the table price [list]; null when either is missing or the table price is not positive. Negative = markup.
num? discountPercent(Object? price, num? list) {
  if (price is! num || list == null || list <= 0) return null;
  return (1 - price / list) * 100;
}

/// Highest discount against the list price (and the index of that line) and how many typed prices have no list price to compare with.
/// A line counts only when it has a numeric price and a product whose price info was looked up ([hasPriceInfo]); [listPrice] gives the table price.
({num discount, int line, int offList}) summarizePricing(
  List<Map<String, dynamic>> lines, {
  required bool Function(Object id) hasPriceInfo,
  required num? Function(Object id) listPrice,
}) {
  num best = 0;
  var line = -1;
  var off = 0;
  for (final (i, l) in lines.indexed) {
    final price = l['unitPrice'];
    final id = l['productId'];
    if (price is! num || id == null || !hasPriceInfo(id)) continue;
    final d = discountPercent(price, listPrice(id));
    if (d == null) {
      off++;
    } else if (d > best) {
      best = d;
      line = i;
    }
  }
  return (discount: best, line: line, offList: off);
}

/// Sales staff delete only a brand-new draft; an admin also clears drafts of any revision and quotes that ended without an order.
bool canDeleteQuote(Session s, Object? status, int revision) =>
    s.isAdmin ? const ['Draft', 'Cancelled', 'Rejected', 'Expired'].contains(status) : status == 'Draft' && revision == 0;

/// Small alert text for a quote row/card: the most urgent thing the salesperson should know.
String quoteAlert(Map<String, dynamic> e) => quoteAlerts(e).map((a) => a.text).join(' · ');

/// Every alert a quote row has (a quote can both need an answer and be about to expire), with the tone and icon that mark it.
List<({String text, Tone tone, IconData icon})> quoteAlerts(Map<String, dynamic> e) => [
  if (e['status'] == 'PendingApproval' || e['needsApproval'] == true && e['status'] == 'Draft') quoteAlertSpecs['discount']!,
  if (e['followUp'] == true) quoteAlertSpecs['followup']!,
  if (e['expiring'] == true) quoteAlertSpecs['expiring']!,
];
