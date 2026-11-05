import 'package:ebt_engenharia/screens/sales_common.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double width, Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
);

void main() {
  testWidgets('the stage path uses short labels when the steps are tight and full ones when there is room', (tester) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(1200, const StagePath(steps: flowSteps, current: 3)));
    expect(find.text('OF'), findsOneWidget);
    expect(find.text('Ordem de Fabricação'), findsNothing);
    expect(find.text('Ped. compra'), findsOneWidget);
    await tester.pumpWidget(_host(1700, const StagePath(steps: flowSteps, current: 3)));
    expect(find.text('Ordem de Fabricação'), findsOneWidget);
  });

  testWidgets('grouped timeline says the day once, only the time per entry, and the user only when it is someone else', (tester) async {
    final entries = [
      const TimelineEntry(title: 'Aprovação do cliente', at: '2026-11-04T19:58:00', user: 'admin'),
      const TimelineEntry(title: 'Envio registrado', at: '2026-11-03T13:20:00', user: 'maria'),
      const TimelineEntry(title: 'Criação', at: '2026-11-03T13:19:00', user: 'admin'),
    ];
    await tester.pumpWidget(_host(400, TimelineView(entries: entries, groupByDay: true, hideUser: 'admin')));
    expect(find.text('04/11/2026'), findsOneWidget);
    expect(find.text('03/11/2026'), findsOneWidget); // one heading for two entries of the same day
    expect(find.text('19:58'), findsOneWidget); // current user: time only
    expect(find.text('13:20 · maria'), findsOneWidget);
  });

  testWidgets('the header can lay its fields out side by side', (tester) async {
    await tester.pumpWidget(
      _host(
        900,
        const RecordHeader(icon: Icons.request_quote_outlined, kind: 'Orçamento comercial', title: 'PROP 18', fields: [('Cliente', 'Cliente teste'), ('Frete', 'CIF')], inlineFields: true),
      ),
    );
    final cliente = tester.getTopLeft(find.text('Cliente'));
    final frete = tester.getTopLeft(find.text('Frete'));
    expect((cliente.dy - frete.dy).abs(), lessThan(4), reason: 'same row');
    expect(tester.getTopLeft(find.text('Cliente teste')).dx, greaterThan(cliente.dx));
    expect(tester.getTopLeft(find.text('Cliente teste')).dy, closeTo(cliente.dy, 4), reason: 'value beside its label, not under it');
  });
}
