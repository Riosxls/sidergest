import 'dart:math' as math;

import 'package:ebt_engenharia/api.dart';
import 'package:ebt_engenharia/screens/dashboard.dart' show modules;
import 'package:ebt_engenharia/screens/modules.dart';
import 'package:ebt_engenharia/screens/shell.dart';
import 'package:ebt_engenharia/session.dart';
import 'package:ebt_engenharia/widgets/alerts.dart';
import 'package:ebt_engenharia/widgets/command_palette.dart';
import 'package:ebt_engenharia/widgets/discard_guard.dart';
import 'package:ebt_engenharia/widgets/pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_test.dart' show json, openPalette, page, pumpShell;
import 'nav.dart';

/// A new Shell on an existing session, as after an idle lock.
Future<void> pumpAgain(WidgetTester tester, Session session, {void Function()? whileClosed}) async {
  await tester.pumpWidget(const SizedBox());
  whileClosed?.call();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Shell(session: session),
    ),
  );
  await tester.pumpAndSettle();
}

ListTile tile(WidgetTester tester, String key) => tester.widget<ListTile>(find.byKey(ValueKey(key)));

double luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
}

void main() {
  testWidgets('Saldos groups its four tabs, Locais included, and Locais has no sidebar entry of its own', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'Estoque', 'balances');
    for (final id in ['balances', 'low-stock', 'reservations', 'locations']) {
      expect(find.byKey(ValueKey('tab-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('nav-locations')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-locations')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tab-locations'))).selected, isTrue);
    expect(tile(tester, 'nav-balances').selected, isTrue);
  });

  testWidgets('screens named after an API path keep their place in the saved location and come back after a lock', (tester) async {
    final (session, _) = await pumpShell(tester, 'Admin');
    await openScreen(tester, 'Engenharia', '/api/materials');
    await tester.tap(find.byKey(const ValueKey('tab-/api/material-classes')));
    await tester.pumpAndSettle();
    expect(Shell.lastLocation[session]!.path, '/s/%2Fapi%2Fmaterial-classes');
    await pumpAgain(tester, session);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tab-/api/material-classes'))).selected, isTrue);
  });

  testWidgets('a pasted link to an API-path screen is recognised', (tester) async {
    await pumpShell(tester, 'Admin');
    await openPalette(tester);
    await tester.enterText(find.byType(TextField).last, '/s/%2Fapi%2Fmaterials');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir link colado'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tab-/api/materials'))).selected, isTrue);
  });

  testWidgets('switching tabs is not a trip: Back leaves the group, and the tabs stay out of Recentes', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'Estoque', 'balances');
    await tester.tap(find.byKey(const ValueKey('tab-low-stock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-reservations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    // One Back from the third tab lands on the module overview, where the group was entered from.
    expect(find.byKey(const ValueKey('tab-balances')), findsNothing);
    expect(find.byKey(const ValueKey('nav-section-Estoque')), findsOneWidget);
    final recents = [for (final r in await RecentStore.load()) r.id];
    expect(recents, contains('balances'));
    expect(recents, isNot(contains('low-stock')));
    expect(recents, isNot(contains('reservations')));
  });

  testWidgets('the app bar names the module, the group and the tab', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'Comercial', 'deliveries');
    expect(find.text('Comercial › Expedição › Entregas'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-certificates')));
    await tester.pumpAndSettle();
    expect(find.text('Comercial › Expedição › Certificados'), findsOneWidget);
    await openScreen(tester, 'Estoque', 'balances');
    // A tab named like its group is not said twice.
    expect(find.text('Estoque › Saldos'), findsOneWidget);
  });

  testWidgets('a group label that only repeats its single entry is left out', (tester) async {
    await pumpShell(tester, 'Admin');
    await openModule(tester, 'Comercial');
    expect(find.text('Vendas'), findsOneWidget);
    expect(find.text('Relatórios'), findsOneWidget);
    expect(find.text('Preços e regras'), findsOneWidget);
  });

  testWidgets('inside a module the other modules are one tap away', (tester) async {
    await pumpShell(tester, 'Admin');
    await openModule(tester, 'Estoque');
    expect(find.byKey(const ValueKey('nav-module:PCP')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-switch-module')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-module:PCP')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-section-PCP')), findsOneWidget);
  });

  testWidgets('a phone app bar keeps its room for the title: no menu, search or bell, which the bottom bar already has', (tester) async {
    final (session, _) = await pumpShell(tester, 'Production', size: const Size(400, 800));
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget); // the bottom bar's Buscar
    expect(find.byTooltip('Notificações (1)'), findsNothing);
    final semantics = tester.ensureSemantics();
    session.alerts.value = const [AlertInfo(Icons.block, 'x', 3, 'production-orders')];
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Alertas, 3 pendentes'), findsOneWidget);
    expect(find.bySemanticsLabel('Início'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the bell is fed by the shell too, when another screen than the Painel is the one in use', (tester) async {
    final (session, log) = await pumpShell(tester, 'Production');
    await openScreen(tester, 'PCP', 'production-orders');
    session.alerts.value = const [];
    final before = log.where((r) => r.url.path == '/api/production/orders/dashboard').length;
    await tester.pump(const Duration(minutes: 3, seconds: 1));
    await tester.pumpAndSettle();
    expect(log.where((r) => r.url.path == '/api/production/orders/dashboard').length, greaterThan(before));
    expect(session.alerts.total, greaterThan(0));
  });

  testWidgets('the place left is offered again only to the same user, and its 30 minutes start when the Shell closes', (tester) async {
    final (session, _) = await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    final old = DateTime.now().subtract(const Duration(minutes: 29));
    await pumpAgain(tester, session, whileClosed: () => Shell.lastLocation[session] = (path: '/s/production-orders', at: old, user: 'ana'));
    expect(find.byKey(const ValueKey('nav-section-PCP')), findsOneWidget);
    expect(Shell.lastLocation[session]!.at.isAfter(old), isTrue);

    await pumpAgain(tester, session, whileClosed: () => Shell.lastLocation[session] = (path: '/s/production-orders', at: DateTime.now(), user: 'bia'));
    expect(find.byKey(const ValueKey('module-PCP')), findsOneWidget); // the Painel

    await openScreen(tester, 'PCP', 'production-orders');
    session.signedOutManually = true;
    await tester.pumpWidget(const SizedBox());
    expect(Shell.lastLocation[session], isNull);
  });

  testWidgets('a pasted link waits for the answer to "discard changes?" before it opens anything', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'PCP', 'production-orders');
    final inner = tester.state<NavigatorState>(find.byType(Navigator).last);
    inner.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'record:quote:5'),
        builder: (_) => DiscardGuard(
          isDirty: () => true,
          child: const Scaffold(body: Text('editando')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openPalette(tester);
    await tester.enterText(find.byType(TextField).last, '/s/customers/r/customer/3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir link colado'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('editando'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-customers')), findsNothing); // still inside PCP
  });

  testWidgets('the tab strip scrolls the selected tab into view on a phone and moves with the arrow keys', (tester) async {
    await pumpShell(tester, 'Admin', size: const Size(400, 800));
    await openScreen(tester, 'Comercial', '/api/sales/price-list');
    // Reached from search (a link or an alert would do the same): the strip must show where we are.
    expect(tester.getRect(find.byKey(const ValueKey('tab-/api/fiscal/tax-rules'))).right, greaterThan(400));
    await openPalette(tester);
    await tester.enterText(find.byType(TextField).last, 'regras de imposto');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regras de imposto').last);
    await tester.pumpAndSettle();
    final right = tester.getRect(find.byKey(const ValueKey('tab-/api/fiscal/tax-rules'))).right;
    expect(right, lessThanOrEqualTo(400));
    // Left from the last tab selects the one before it.
    // Tab until a chip of the strip has the focus.
    for (var i = 0; i < 40; i++) {
      if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ChoiceChip>() != null) break;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ChoiceChip>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // Right from the last tab goes nowhere; left from it selects the one before.
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tab-/api/fiscal/tax-rules'))).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('tab-/api/sales/payment-terms'))).selected, isTrue);
  });

  testWidgets('a group is one card on the phone overview, naming its tabs', (tester) async {
    await pumpShell(tester, 'Admin', size: const Size(400, 800));
    await openModule(tester, 'Comercial');
    expect(find.text('Expedição'), findsWidgets);
    expect(find.text('Entregas · Certificados · Notas fiscais · Contas a receber'), findsOneWidget);
  });

  testWidgets('pinned tabs and the collapsed sidebar: a tab pin names its group, and pins stay reachable as stars', (tester) async {
    await pumpShell(tester, 'Admin');
    await openScreen(tester, 'Comercial', 'deliveries');
    await tester.tap(find.byKey(const ValueKey('tab-certificates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pin-screen')));
    await tester.pumpAndSettle();
    expect(find.text('Expedição · Certificados'), findsOneWidget);
    await tester.tap(find.byTooltip('Recolher menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-pin-certificates-')), findsOneWidget);
  });

  testWidgets('search lists a screen whose name matches before one that merely sits under a matching module, and a tab names its group', (tester) async {
    await pumpShell(tester, 'Admin');
    await openPalette(tester);
    await tester.enterText(find.byType(TextField).last, 'estoque');
    await tester.pumpAndSettle();
    final first = find.descendant(of: find.byType(Dialog), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: first, matching: find.text('Módulos')), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'reservas');
    await tester.pumpAndSettle();
    expect(find.text('Estoque › Saldos'), findsOneWidget);
  });

  testWidgets('the path steps are announced with their state, reachable by keyboard, and white on the accents reads at 4.5:1', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return StagePath(steps: const [PathStep('A'), PathStep('B'), PathStep('C')], current: 1, onStep: (i) => i == 0 ? () => opened++ : null);
            },
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Etapa 1 de 3: A, concluída'), findsOneWidget);
    expect(find.bySemanticsLabel('Etapa 2 de 3: B, atual'), findsOneWidget);
    expect(find.bySemanticsLabel('Etapa 3 de 3: C, a fazer'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);
    for (final tone in [Tone.success, Tone.danger]) {
      expect(contrast(Colors.white, toneAccent(ctx, tone)), greaterThanOrEqualTo(4.5), reason: '$tone');
    }
    semantics.dispose();
  });

  testWidgets('a module overview that fails to load offers to try again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var up = false;
    final session = Session(
      api: ApiClient(baseUrl: 'http://api.test', token: 'tok', client: MockClient((r) async => up ? json(page([])) : http.Response('boom', 500))),
    )..permissions = const {'read'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModuleScreen(session: session, module: modules.first, links: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No "Atualizado às" for numbers that were never read, and a button to read them again.
    expect(find.textContaining('Atualizado às'), findsNothing);
    expect(find.byKey(const ValueKey('module-retry')), findsOneWidget);
    up = true;
    await tester.tap(find.byKey(const ValueKey('module-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-retry')), findsNothing);
  });

  testWidgets('Primeiros passos ignores a section that did not load instead of counting it as done', (tester) async {
    await pumpShell(tester, 'Production');
    expect(find.text('Primeiros passos'), findsOneWidget);
    // Steps count only the sections that answered; "x de y" never claims more than was read.
    final count = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ de \d+$').hasMatch(w.data ?? ''));
    final m = RegExp(r'(\d+) de (\d+)').firstMatch(tester.widget<Text>(count).data!)!;
    expect(int.parse(m[1]!), lessThanOrEqualTo(int.parse(m[2]!)));
  });
}
