import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/widgets/record_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 1000}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(key: const ValueKey('host'), width: width, child: child),
    ),
  ),
);

void main() {
  setUp(() {});

  testWidgets('InfoGrid: short pairs share equal columns and a long value gets a row of its own', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const address = 'Rua Caraguatatuba 161, Jardim Vista Alegre, Embu das Artes - SP, 06807230';
    await tester.pumpWidget(_host(const InfoGrid([('Local de entrega', address), ('Criada', 'admin · 30/10/2026'), ('Enviada', '30/10/2026 10:20'), ('Aprovada', 'ana · 31/10/2026')])));

    final addressTop = tester.getTopLeft(find.text(address));
    final created = tester.getTopLeft(find.text('admin · 30/10/2026'));
    final sent = tester.getTopLeft(find.text('30/10/2026 10:20'));
    final approved = tester.getTopLeft(find.text('ana · 31/10/2026'));
    expect(created.dy, greaterThan(addressTop.dy + 20), reason: 'the address does not share a row with the next pair');
    expect(created.dx, addressTop.dx, reason: 'first column starts at the card edge');
    expect(sent.dy, created.dy);
    expect(approved.dy, created.dy);
    expect(sent.dx - created.dx, approved.dx - sent.dx, reason: 'equal column pitch');
    expect(sent.dx - created.dx, greaterThan(210), reason: 'a real gap between columns, not text touching text');
  });

  testWidgets('SimpleTable: first column on the left edge, last column on the right edge, header and values share an alignment', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rows = [
      {'item': '10', 'desc': 'TUBO-C 06,00 X 0,90 X 6000 MM', 'total': 'R\$ 11.895,00'},
      {'item': '20', 'desc': 'TUBO-C 08,00', 'total': 'R\$ 950,00'},
    ];
    await tester.pumpWidget(
      _host(
        SimpleTable(
          columns: [
            ColumnSpec('Item', (e) => '${e['item']}'),
            ColumnSpec('Descrição', (e) => '${e['desc']}'),
            ColumnSpec('Total', (e) => '${e['total']}', numeric: true),
          ],
          rows: rows,
        ),
      ),
    );
    final host = tester.getRect(find.byKey(const ValueKey('host')));
    expect(tester.getTopLeft(find.text('Item')).dx, host.left, reason: 'header starts at the card edge, not 24 px inside');
    expect(tester.getTopRight(find.text('Total')).dx, host.right, reason: 'last header ends at the card edge');
    expect(tester.getTopRight(find.text('R\$ 11.895,00')).dx, host.right);
    expect(tester.getTopRight(find.text('R\$ 950,00')).dx, host.right, reason: 'numbers right-align under their header');
  });

  testWidgets('SimpleTable scrolls instead of overflowing when the content is wider than the card', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        SimpleTable(
          columns: [for (var i = 0; i < 8; i++) ColumnSpec('Coluna $i', (e) => 'valor bem comprido número ${e['n']}')],
          rows: [
            {'n': 1},
          ],
        ),
        width: 600,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

  testWidgets('TotalsBlock: every value ends on the same right edge and the total is bold', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const TotalsBlock([('Produtos', 'R\$ 11.895,00'), ('IPI', 'R\$ 0,00'), ('Total', 'R\$ 11.895,00')])));
    final host = tester.getRect(find.byKey(const ValueKey('host')));
    final a = tester.getTopRight(find.text('R\$ 0,00')).dx;
    expect(a, host.right);
    for (final t in tester.widgetList<Text>(find.text('R\$ 11.895,00'))) {
      expect(t.data, 'R\$ 11.895,00');
    }
    final last = tester.widget<Text>(find.text('R\$ 11.895,00').last);
    expect(last.style?.fontWeight, FontWeight.w700);
    expect(tester.getTopLeft(find.text('Total')).dx, greaterThan(host.right - 300 - 1), reason: 'block is right-aligned, 300 px wide');
  });
}
