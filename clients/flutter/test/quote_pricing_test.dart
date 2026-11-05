import 'package:ebt_engenharia/screens/quote_pricing.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart' show Tone;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmtFileSize switches from KB to MB at 1 MiB and uses a decimal comma', () {
    expect(fmtFileSize(null), '0 KB');
    expect(fmtFileSize(1), '1 KB');
    expect(fmtFileSize(2048), '2 KB');
    expect(fmtFileSize(1048576), '1,0 MB');
    expect(fmtFileSize(1572864), '1,5 MB');
  });

  test('lineEstimate adds IPI and ICMS on the base value', () {
    expect(lineEstimate({'quantity': 10, 'unitPrice': 100}), 1000);
    expect(lineEstimate({'quantity': 10, 'unitPrice': 100, 'ipiPercent': 5, 'icmsPercent': 12}), 1170);
    expect(lineEstimate({'quantity': 'x'}), 0);
  });

  test('estimateParts sums products, IPI and ICMS', () {
    final p = estimateParts([
      {'quantity': 2, 'unitPrice': 50, 'ipiPercent': 10, 'icmsPercent': 0},
      {'quantity': 1, 'unitPrice': 100, 'ipiPercent': 0, 'icmsPercent': 18},
      {'quantity': 5},
    ]);
    expect((p.products, p.ipi, p.icms), (200, 10, 18));
  });

  group('discountPercent', () {
    test('discount, markup and equal price', () {
      expect(discountPercent(90, 100), closeTo(10, 1e-9));
      expect(discountPercent(110, 100), closeTo(-10, 1e-9));
      expect(discountPercent(100, 100), 0);
    });

    test('null without a numeric price or a positive table price', () {
      expect(discountPercent(null, 100), isNull);
      expect(discountPercent('90', 100), isNull);
      expect(discountPercent(90, null), isNull);
      expect(discountPercent(90, 0), isNull);
    });
  });

  group('summarizePricing', () {
    final list = <int, num?>{1: 100, 2: 200, 3: null};
    ({num discount, int line, int offList}) run(List<Map<String, dynamic>> lines, {Set<int>? known}) =>
        summarizePricing(lines, hasPriceInfo: (id) => (known ?? {1, 2, 3}).contains(id), listPrice: (id) => list[id]);

    test('picks the line with the highest discount', () {
      final r = run([
        {'productId': 1, 'unitPrice': 95},
        {'productId': 2, 'unitPrice': 150},
        {'productId': 1, 'unitPrice': 80},
      ]);
      expect(r.discount, closeTo(25, 1e-9));
      expect((r.line, r.offList), (1, 0));
    });

    test('counts typed prices that have no table price, and skips lines without info', () {
      final r = run([
        {'productId': 3, 'unitPrice': 10},
        {'productId': 1, 'unitPrice': 100},
        {'productId': 2, 'unitPrice': 1},
        {'productId': 1},
      ], known: {1, 3});
      expect((r.discount, r.line, r.offList), (0, -1, 1));
    });

    test('a markup is never the best discount', () {
      final r = run([
        {'productId': 1, 'unitPrice': 120},
      ]);
      expect((r.discount, r.line), (0, -1));
    });
  });

  test('quoteAlerts lists every alert in order, quoteAlert joins them', () {
    final e = {'status': 'PendingApproval', 'followUp': true, 'expiring': true};
    expect(quoteAlerts(e).map((a) => a.text), ['Desconto acima do limite', 'Cobrar resposta', 'Vence em breve']);
    expect(quoteAlerts(e).last.tone, Tone.warning);
    expect(quoteAlert(e), 'Desconto acima do limite · Cobrar resposta · Vence em breve');
    expect(quoteAlerts({'status': 'Draft', 'needsApproval': true}).single.text, 'Desconto acima do limite');
    expect(quoteAlerts({'status': 'Sent'}), isEmpty);
  });
}
