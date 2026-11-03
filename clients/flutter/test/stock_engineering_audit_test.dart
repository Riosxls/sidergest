import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/entities.dart';
import 'package:ebt_engenharia/screens/entity_list.dart';
import 'package:ebt_engenharia/screens/product_detail.dart';
import 'package:ebt_engenharia/screens/stock_documents.dart';
import 'package:ebt_engenharia/screens/stock_lots.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/record_list.dart' show NameCache;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'role_permissions.dart';
import 'stock_purchasing_test.dart' show Fake, json, page, pick, pumpScreen;

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  // The name cache is shared by every test of the process; a lookup left open by one test must not answer the next.
  setUp(NameCache.clear);

  group('lotes e reservas', () {
    testWidgets('the lot dialog leads to the stock of its item, a record page with its own links', (tester) async {
      final fake = Fake();
      await pumpScreen(tester, fake, (s) => LotsView(session: s));
      await tester.tap(find.text('L-3'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'lot-open-item');
      // The page loads the item by id: its title is the code and description.
      expect(find.text('BOB-15 · Bobina 1,5mm'), findsOneWidget);
      expect(find.text('Disponibilidade'), findsWidgets);
      expect(find.byKey(const ValueKey('related-menu')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('related-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Cadastro do material'), findsOneWidget);
      expect(find.text('Onde é usado'), findsOneWidget);
    });

    testWidgets('a failed inspection is said inside the dialog, which stays open', (tester) async {
      final fake = Fake()..inspectionFails = true;
      await pumpScreen(tester, fake, (s) => LotsView(session: s));
      await tester.tap(find.text('L-3'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'lot-release');
      expect(find.byKey(const ValueKey('lot-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('lot-release')), findsOneWidget);
    });

    testWidgets('a reservation opens its details; releasing the balance is a button there', (tester) async {
      final fake = Fake()
        ..reservations.add({
          'id': 5,
          'materialId': 4,
          'productId': null,
          'locationId': null,
          'quantity': 100,
          'consumed': 0,
          'remaining': 100,
          'status': 'Open',
          'reference': 'OF 9',
          'neededOn': null,
          'createdBy': 'u',
          'createdAt': '2026-10-20T10:00:00Z',
        });
      await pumpScreen(tester, fake, (s) => ReservationsView(session: s));
      await tester.tap(find.text('OF 9'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/stock/reservations/5/release'), isFalse);
      await tapKey(tester, 'reservation-release');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(fake.has('POST', '/api/stock/reservations/5/release'), isTrue);
    });
  });

  group('novo lançamento', () {
    Future<void> chooseType(WidgetTester tester, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a problem is shown at the top of the form, and a line without quantity is named', (tester) async {
      final fake = Fake();
      await pumpScreen(tester, fake, (s) => StockPostScreen(session: s));
      await tapKey(tester, 'post-stock');
      expect(find.byKey(const ValueKey('post-message')), findsOneWidget);
      expect(find.text('Escolha o tipo do lançamento'), findsOneWidget);
      await chooseType(tester, 'Entrada de compra');
      await tester.tap(find.byKey(const ValueKey('add-line')));
      await tester.pumpAndSettle();
      await pick(tester, 'locationId', 'ALM · Almoxarifado');
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '5');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'post-stock');
      expect(find.text('Linha 1: informe o material ou o produto'), findsOneWidget);
      expect(fake.has('POST', '/api/stock/documents'), isFalse);
    });

    testWidgets('changing the type asks first and drops the lines typed for the old one', (tester) async {
      final fake = Fake();
      await pumpScreen(tester, fake, (s) => StockPostScreen(session: s, type: 'Receipt'));
      await tester.tap(find.byKey(const ValueKey('add-line')));
      await tester.pumpAndSettle();
      await pick(tester, 'materialId', 'BOB-15 · Bobina 1,5mm');
      await pick(tester, 'locationId', 'ALM · Almoxarifado');
      await tester.enterText(find.byKey(const ValueKey('field-quantity')), '5');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Linhas (1)'), findsOneWidget);
      await chooseType(tester, 'Requisição (consumo)');
      expect(find.text('Trocar o tipo do lançamento?'), findsOneWidget);
      // Keeping the type keeps the line.
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Linhas (1)'), findsOneWidget);
      await chooseType(tester, 'Requisição (consumo)');
      await tapKey(tester, 'confirm-step');
      expect(find.text('Linhas (0)'), findsOneWidget);
    });
  });

  group('cadastros', () {
    testWidgets('rarely used material fields stay folded, units are upper case and a delete names the record', (tester) async {
      final fake = Fake()..role = 'Admin';
      await pumpScreen(tester, fake, (s) => EntityListScreen(session: s, spec: materials));
      await tester.tap(find.text('Novo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-ncm')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('field-stockUnit')), 'kg');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('field-stockUnit'))).controller!.text, 'KG');
      await tapKey(tester, 'form-more');
      expect(find.byKey(const ValueKey('field-ncm')), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      // An existing record: the delete asks with the name of the record.
      await tester.tap(find.text('BOB-15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir Material BOB-15?'), findsOneWidget);
      expect(find.textContaining('recusa a exclusão'), findsOneWidget);
    });

    testWidgets('the row menu of a material leads to its stock', (tester) async {
      final fake = Fake()..role = 'Admin';
      await pumpScreen(tester, fake, (s) => EntityListScreen(session: s, spec: materials));
      await tester.tap(find.byTooltip('Ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saldo e movimentos'));
      await tester.pumpAndSettle();
      expect(find.text('BOB-15 · Bobina 1,5mm'), findsOneWidget);
      expect(find.text('Kardex'), findsOneWidget);
    });
  });

  group('produto', () {
    Future<Session> pumpProduct(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = MockClient((r) async {
        final p = r.url.path;
        if (p == '/api/products/7') {
          return json({'id': 7, 'code': 'TB-1', 'name': 'Tubo', 'kind': 'Part', 'ncm': '7306', 'stockUnit': 'PC', 'drawingRevision': 'B', 'processRevision': null, 'blocked': false});
        }
        if (p == '/api/products/7/revisions') {
          return json([
            {'kind': 'Drawing', 'code': 'B', 'createdAt': '2026-10-01T10:00:00Z', 'user': 'ana', 'reason': null},
          ]);
        }
        if (p == '/api/products/7/routing' || p == '/api/products/7/where-used') return json(<Object>[]);
        if (p == '/api/products/7/bom/explode') return json({'lines': <Object>[], 'materials': <Object>[]});
        return json(page([]));
      });
      final session = Session(api: ApiClient(baseUrl: 'http://api.test', client: client, token: 'tok'))
        ..username = 'u'
        ..role = 'Admin'
        ..permissions = rolePermissions['Admin']!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ProductDetailScreen(session: session, productId: 7),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('an empty routing says what happens to an OF and offers the first operation', (tester) async {
      await pumpProduct(tester);
      expect(find.text('Sem operações no roteiro'), findsOneWidget);
      expect(find.textContaining('processo sugerido'), findsOneWidget);
      expect(find.byKey(const ValueKey('routing-first')), findsOneWidget);
    });

    testWidgets('a revision chip jumps to the Revisões tab, where revisions are changed', (tester) async {
      await pumpProduct(tester);
      expect(find.text('Desenho rev. B'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Desenho rev. B'));
      await tester.pumpAndSettle();
      // The chip plus the history row of the tab that is now showing.
      expect(find.text('Desenho rev. B'), findsNWidgets(2));
    });

    testWidgets('the link menu offers the stock, where it is used and the revisions', (tester) async {
      await pumpProduct(tester);
      await tester.tap(find.byKey(const ValueKey('related-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Saldo em estoque'), findsOneWidget);
      expect(find.text('Onde é usado'), findsWidgets);
      expect(find.text('Revisões'), findsWidgets);
    });
  });
}
