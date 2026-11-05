import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart' show friendlyError;
import '../entities.dart';
import '../session.dart';
import '../widgets/alerts.dart';
import '../widgets/command_palette.dart';
import '../widgets/discard_guard.dart';
import '../widgets/record_nav.dart';
import '../widgets/tab_frame.dart';
import '../widgets/unload_guard.dart';
import '../widgets/user_menu.dart';
import 'audit.dart';
import 'certificates.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'deliveries.dart';
import 'entity_list.dart';
import 'fiscal.dart';
import 'low_stock.dart';
import 'modules.dart';
import 'orders.dart';
import 'permissions.dart';
import 'product_detail.dart';
import 'production_floor.dart';
import 'production_orders.dart';
import 'quick_actions.dart';
import 'quotations.dart';
import 'receipts.dart';
import 'receivables.dart';
import 'record_links.dart';
import 'reports.dart' show BillingSummaryScreen, MaterialConsumptionScreen;
import 'requisitions.dart';
import 'sales_common.dart' show openDelivery, openQuote, openSalesOrder;
import 'sales_orders.dart';
import 'sales_pipeline.dart';
import 'sales_quotes.dart';
import 'steel.dart';
import 'stock_balances.dart';
import 'stock_closing.dart';
import 'stock_documents.dart';
import 'stock_lots.dart';
import 'suppliers.dart';
import 'users.dart';
import 'viability.dart';

/// An entry of the sidebar navigation of the [Shell].
class NavItem {
  const NavItem(this.id, this.icon, this.title, this.section, this.build, {this.admin = false});

  final String id;
  final IconData icon;
  final String title;
  final String section;
  final Widget Function(Session s, String? filter, Navigate go) build;

  /// Listed only for sessions with the 'admin' permission.
  final bool admin;
}

const hiddenSection = '_module';

/// Screens that share one sidebar entry. The first tab is the entry; every tab stays a screen of its own (links, alerts, pins and search still reach it).
final tabGroups = <TabGroup>[
  // Shipping and the money that follows it (NF, contas a receber) share one entry.
  const TabGroup('Comercial', 'Expedição e financeiro', Icons.local_shipping_outlined, [
    (id: 'deliveries', label: 'Entregas'),
    (id: 'certificates', label: 'Certificados'),
    (id: 'fiscal-documents', label: 'Notas fiscais'),
    (id: 'receivables', label: 'Contas a receber'),
  ]),
  const TabGroup('Comercial', 'Relatórios', Icons.bar_chart_outlined, [
    (id: 'report-material-consumption', label: 'Consumo de material'),
    (id: 'report-billing', label: 'Faturamento'),
  ]),
  TabGroup('Comercial', 'Preços e regras', Icons.price_change_outlined, [
    (id: priceList.path, label: 'Tabela de preços'),
    (id: monthlyPrices.path, label: 'Preços mensais da NF'),
    (id: paymentTerms.path, label: 'Prazos'),
    (id: taxRules.path, label: 'Regras de imposto'),
  ]),
  TabGroup('Engenharia', 'Materiais', Icons.category_outlined, [
    (id: materials.path, label: 'Materiais'),
    (id: materialClasses.path, label: 'Classes'),
    (id: materialGroups.path, label: 'Grupos'),
    (id: materialSubgroups.path, label: 'Subgrupos'),
  ]),
  TabGroup('Engenharia', 'Processo e recursos', Icons.precision_manufacturing_outlined, [
    (id: machines.path, label: 'Máquinas'),
    (id: workCenters.path, label: 'Centros de trabalho'),
    (id: tools.path, label: 'Ferramentas'),
    (id: standardOperations.path, label: 'Operações padrão'),
  ]),
  const TabGroup('Estoque', 'Saldos', Icons.inventory_outlined, [
    (id: 'balances', label: 'Saldos'),
    (id: 'low-stock', label: 'Estoque mínimo'),
    (id: 'reservations', label: 'Reservas'),
    (id: 'locations', label: 'Locais'),
  ]),
  const TabGroup('Estoque', 'Movimentações', Icons.swap_horiz, [(id: 'documents', label: 'Movimentações'), (id: 'closing', label: 'Fechamento e custo médio')]),
  const TabGroup('Suprimentos', 'Pedidos de compra', Icons.receipt_long_outlined, [(id: 'orders', label: 'Pedidos de compra'), (id: 'overdue', label: 'Em atraso')]),
  const TabGroup('PCP', 'Ordens de fabricação', Icons.assignment_outlined, [
    (id: 'production-orders', label: 'Ordens de fabricação'),
    (id: 'outside-processing', label: 'Beneficiamento externo'),
  ]),
  TabGroup('PCP', 'Cadastros', Icons.groups_outlined, [
    (id: employees.path, label: 'Funcionários'),
    (id: shifts.path, label: 'Turnos'),
    (id: occurrences.path, label: 'Ocorrências'),
    (id: holidays.path, label: 'Feriados'),
  ]),
];

TabGroup? tabGroupOf(String id) {
  for (final g in tabGroups) {
    if (g.has(id)) return g;
  }
  return null;
}

List<NavItem> navItems() {
  final base = _screens();
  final links = {
    for (final m in modules) m.section: [
      for (final i in base.where((i) => i.section == m.section))
        // A group is one card, on its first tab.
        if (tabGroupOf(i.id) == null)
          ModuleLink(i.id, i.icon, i.title)
        else if (tabGroupOf(i.id)!.tabs.first.id == i.id)
          ModuleLink(i.id, tabGroupOf(i.id)!.icon, tabGroupOf(i.id)!.title, subtitle: tabGroupOf(i.id)!.tabs.map((t) => t.label).join(' · ')),
    ],
  };
  return [
    ...base,
    for (final m in modules)
      NavItem(m.id, m.icon, m.section, hiddenSection, (s, f, go) => ModuleScreen(session: s, module: m, links: links[m.section]!, onNavigate: go)),
  ];
}

List<NavItem> _screens() => [
  NavItem('dashboard', Icons.dashboard_outlined, 'Painel', '', (s, f, go) => DashboardScreen(session: s, onNavigate: go)),
  NavItem('customers', Icons.people_outline, 'Clientes', 'Comercial', (s, f, go) => CustomersScreen(session: s)),
  NavItem('sales-pipeline', Icons.view_kanban_outlined, 'Funil de vendas', 'Comercial', (s, f, go) => SalesPipelineScreen(session: s)),
  NavItem('sales-quotes', Icons.request_quote_outlined, 'Orçamentos', 'Comercial', (s, f, go) => QuotesScreen(session: s)),
  NavItem('viability', Icons.fact_check_outlined, 'Análises de viabilidade', 'Comercial', (s, f, go) => ViabilityScreen(session: s, initialStatus: f)),
  NavItem('sales-orders', Icons.receipt_long_outlined, 'Pedidos de venda', 'Comercial', (s, f, go) => SalesOrdersScreen(session: s, initialFilter: f)),
  NavItem('deliveries', Icons.local_shipping_outlined, 'Entregas', 'Comercial', (s, f, go) => DeliveriesScreen(session: s, initialFilter: f)),
  NavItem('certificates', Icons.verified_outlined, 'Certificados de qualidade', 'Comercial', (s, f, go) => CertificatesScreen(session: s)),
  NavItem('fiscal-documents', Icons.description_outlined, 'Notas fiscais', 'Comercial', (s, f, go) => FiscalDocumentsScreen(session: s)),
  NavItem('receivables', Icons.account_balance_wallet_outlined, 'Contas a receber', 'Comercial', (s, f, go) => ReceivablesScreen(session: s, initialFilter: f)),
  NavItem('report-material-consumption', Icons.scale_outlined, 'Consumo de material vendido', 'Comercial', (s, f, go) => MaterialConsumptionScreen(session: s)),
  NavItem('report-billing', Icons.bar_chart_outlined, 'Faturamento consolidado', 'Comercial', (s, f, go) => BillingSummaryScreen(session: s)),
  for (final spec in salesMasters) NavItem(spec.path, spec.icon, spec.title, 'Comercial', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  for (final spec in masterData) NavItem(spec.path, spec.icon, spec.title, 'Engenharia', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  NavItem('balances', Icons.inventory_outlined, 'Saldos', 'Estoque', (s, f, go) => BalancesScreen(session: s)),
  NavItem('documents', Icons.swap_horiz, 'Movimentações', 'Estoque', (s, f, go) => DocumentsScreen(session: s)),
  NavItem(
    'lots',
    Icons.verified_outlined,
    'Lotes e inspeção',
    'Estoque',
    (s, f, go) => LotsView(session: s, initialStatus: f ?? (s.canStock ? 'Quarantine' : null)),
  ),
  NavItem('reservations', Icons.bookmark_border, 'Reservas', 'Estoque', (s, f, go) => ReservationsView(session: s)),
  NavItem('low-stock', Icons.trending_down, 'Estoque mínimo', 'Estoque', (s, f, go) => LowStockScreen(session: s)),
  NavItem('steel', Icons.layers_outlined, 'Controle de aço', 'Estoque', (s, f, go) => SteelScreen(session: s)),
  NavItem('closing', Icons.calculate_outlined, 'Fechamento e custo médio', 'Estoque', (s, f, go) => ClosingScreen(session: s)),
  NavItem('locations', stockLocations.icon, stockLocations.title, 'Estoque', (s, f, go) => EntityListScreen(session: s, spec: stockLocations)),
  NavItem('requisitions', Icons.assignment_outlined, 'Requisições', 'Suprimentos', (s, f, go) => RequisitionsScreen(session: s, initialStatus: f)),
  NavItem('quotations', Icons.request_quote_outlined, 'Cotações', 'Suprimentos', (s, f, go) => QuotationsScreen(session: s)),
  NavItem('orders', Icons.receipt_long_outlined, 'Pedidos de compra', 'Suprimentos', (s, f, go) => OrdersScreen(session: s)),
  NavItem('receipts', Icons.move_to_inbox_outlined, 'Recebimentos', 'Suprimentos', (s, f, go) => ReceiptsView(session: s, allowNew: true)),
  NavItem('overdue', Icons.schedule, 'Entregas em atraso', 'Suprimentos', (s, f, go) => OverdueScreen(session: s)),
  NavItem('suppliers', Icons.business_outlined, 'Fornecedores', 'Suprimentos', (s, f, go) => SuppliersScreen(session: s)),
  NavItem('production-orders', Icons.assignment_outlined, 'Ordens de fabricação', 'PCP', (s, f, go) => ProductionOrdersScreen(session: s, initialStatus: f)),
  NavItem('production-reports', Icons.edit_note, 'Apontamentos', 'PCP', (s, f, go) => ReportsScreen(session: s)),
  NavItem('outside-processing', Icons.outbox_outlined, 'Beneficiamento externo', 'PCP', (s, f, go) => OutsideProcessingScreen(session: s)),
  NavItem('planning', Icons.view_timeline_outlined, 'Programação e carga', 'PCP', (s, f, go) => PlanningScreen(session: s)),
  for (final spec in productionMasters) NavItem(spec.path, spec.icon, spec.title, 'PCP', (s, f, go) => EntityListScreen(session: s, spec: spec)),
  NavItem('settings', Icons.tune, 'Parâmetros', 'Sistema', (s, f, go) => SettingsScreen(session: s)),
  NavItem('fiscal-settings', Icons.receipt_outlined, 'Parâmetros fiscais', 'Sistema', (s, f, go) => FiscalSettingsScreen(session: s)),
  NavItem('users', Icons.group_outlined, 'Usuários', 'Sistema', (s, f, go) => UsersScreen(session: s), admin: true),
  NavItem('permissions', Icons.lock_outline, 'Permissões', 'Sistema', (s, f, go) => PermissionsScreen(session: s), admin: true),
  NavItem('audit', Icons.history, 'Auditoria', 'Sistema', (s, f, go) => AuditScreen(session: s), admin: true),
];

/// Screens a user may pick as the one that opens after sign-in, with the label shown in the setting.
List<({String id, String label})> homeScreenChoices(Session s) => [
  for (final i in navItems())
    if (!i.admin || s.isAdmin)
      (id: i.id, label: i.section.isEmpty ? i.title : (i.section == hiddenSection ? 'Visão geral de ${i.title}' : '${i.section}: ${i.title}')),
];

/// Main frame after sign-in: sidebar, module routing and the avatar menu.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  /// Where the user of a [Session] was last. Signing in again on the same session soon after (idle lock, expired session) returns there.
  /// The user is kept with it: another person signing in on the same [Session] never lands on someone else's screen.
  static final lastLocation = Expando<({String path, DateTime at, String? user})>('lastLocation');

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final _items = [
    for (final i in navItems())
      if (!i.admin || widget.session.isAdmin) i,
  ];
  String _current = 'dashboard';
  String? _filter;
  bool _collapsed = false;

  /// Screens left behind by [_go], newest last, so Esc and Back return to the previous screen and not always to the Painel.
  final _history = <({String id, String? filter})>[];

  /// Screens kept alive (filters, sort and scroll survive a visit elsewhere), keyed by [_key]. Oldest first.
  final _mounted = <String, ({String id, String? filter})>{};
  final _left = <String, DateTime>{};
  static const _keepFor = Duration(minutes: 3);
  static const _keepMax = 12;

  /// Who is signed in, kept because the session forgets the name before the Shell closes.
  late final String? _user = widget.session.username;

  /// Keeps the bell current while the Painel (which loads the alerts) is not the screen being used.
  Timer? _alertTimer;
  static const _alertEvery = Duration(minutes: 3);

  /// Wide layout: record pages open inside the content area so the sidebar and the app bar stay.
  final _innerKey = GlobalKey<NavigatorState>();
  final _innerTrail = RecordTrail();
  final _hero = MaterialApp.createMaterialHeroController();
  final _rev = ValueNotifier<int>(0);
  int _inner = 0;
  List<String> _records = const [];
  RecordTop? _top;

  /// Screens undone with Back, so Alt+→ can redo them.
  final _fwd = <({String id, String? filter})>[];

  /// Modules whose screens are listed in the sidebar.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Tile of the screen being shown, kept in view when the sidebar is longer than the window.
  final _activeKey = GlobalKey();

  /// Screens (with their filter) the user starred; listed on top of the sidebar.
  List<({String id, String? filter})> _pins = [];
  AppLifecycleListener? _exit;

  static String _key(String id, String? filter) => '$id/${filter ?? ''}';

  NavigatorState? get _innerNav => _innerKey.currentState;

  /// Context whose Navigator receives pushed record pages: the inner one when it exists.
  BuildContext get _navContext => _innerNav?.overlay?.context ?? context;

  bool get _canBack => _inner > 0 || _history.isNotEmpty || _current != 'dashboard';

  @override
  void initState() {
    super.initState();
    RecordTrail.top.value = null;
    final start = _startLocation();
    if (start != null) {
      _current = start.id;
      _filter = start.filter;
    } else if (_items.any((i) => i.id == widget.session.homeScreen)) {
      _current = widget.session.homeScreen;
    }
    _mount(_current, _filter);
    _remember();
    _restorePrefs();
    // The Painel loads the alerts itself; from any other first screen (home screen setting, a link, an idle-lock return) the bell would stay empty.
    if (_current != 'dashboard') WidgetsBinding.instance.addPostFrameCallback((_) => _loadAlerts());
    _alertTimer = Timer.periodic(_alertEvery, (_) {
      if (_current != 'dashboard') _loadAlerts();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    _innerTrail.pages.addListener(_onInnerPages);
    _innerTrail.records.addListener(_onRecords);
    RecordTrail.top.addListener(_onTop);
    widget.session.addListener(_refreshPages);
    installUnloadGuard(() => DiscardGuard.anyDirty);
    if (!kIsWeb) _exit = AppLifecycleListener(onExitRequested: _onExitRequested);
    final record = start?.record;
    if (record != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRecordByKind(_navContext, widget.session, record.kind, record.id);
      });
    }
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    // The 30 minutes to come back count from the moment the Shell closes, not from the last navigation; a person who signed out is not remembered.
    if (widget.session.signedOutManually) {
      Shell.lastLocation[widget.session] = null;
    } else {
      _remember();
    }
    HardwareKeyboard.instance.removeHandler(_onKey);
    _innerTrail.pages.removeListener(_onInnerPages);
    _innerTrail.records.removeListener(_onRecords);
    RecordTrail.top.removeListener(_onTop);
    widget.session.removeListener(_refreshPages);
    removeUnloadGuard();
    _exit?.dispose();
    _rev.dispose();
    super.dispose();
  }

  void _onRecords() {
    if (mounted) setState(() => _records = _innerTrail.records.value);
  }

  void _onTop() {
    if (!mounted) return;
    setState(() => _top = RecordTrail.top.value);
    _syncLocation();
  }

  /// `/s/<screen>[/r/<kind>/<id>][?f=<filter>]`: the form kept in the address bar (web) and in [Shell.lastLocation].
  /// The screen id is one encoded path segment: master-data screens are named after their API path (`/api/materials`).
  String _location() {
    final r = _top;
    final query = _filter == null ? '' : '?${Uri(queryParameters: {'f': _filter}).query}';
    return '/s/${Uri.encodeComponent(_current)}${_records.isNotEmpty && r != null ? r.path : ''}$query';
  }

  /// Writes the place to [Shell.lastLocation] with the current time.
  void _remember() => Shell.lastLocation[widget.session] = (path: _location(), at: DateTime.now(), user: _user);

  void _syncLocation() {
    _remember();
    if (kIsWeb) unawaited(SystemNavigator.routeInformationUpdated(uri: Uri.parse(_location()), replace: true));
  }

  Future<void> _loadAlerts() async {
    if (!mounted) return;
    await refreshAlertCenter(context, widget.session);
  }

  /// Where to open: the address the browser was loaded with, else the place this user left less than 30 minutes ago.
  ({String id, String? filter, ({String kind, int id})? record})? _startLocation() {
    final fromWeb = kIsWeb ? WidgetsBinding.instance.platformDispatcher.defaultRouteName : null;
    final seen = Shell.lastLocation[widget.session];
    final path = fromWeb != null && fromWeb.startsWith('/s/')
        ? fromWeb
        : (seen != null && seen.user == _user && DateTime.now().difference(seen.at) < const Duration(minutes: 30) ? seen.path : null);
    return path == null ? null : _parse(path);
  }

  ({String id, String? filter, ({String kind, int id})? record})? _parse(String path) {
    final uri = Uri.tryParse(path);
    // `s/<screen>` or `s/<screen>/r/<kind>/<id>`; pathSegments are decoded, so an id such as `/api/materials` survives.
    final seg = uri?.pathSegments;
    if (seg == null || seg.length < 2 || seg[0] != 's' || !_items.any((i) => i.id == seg[1])) return null;
    ({String kind, int id})? record;
    if (seg.length == 5 && seg[2] == 'r' && int.tryParse(seg[4]) != null) {
      record = (kind: seg[3], id: int.parse(seg[4]));
    } else if (seg.length != 2) {
      return null;
    }
    return (id: seg[1], filter: uri!.queryParameters['f'], record: record);
  }

  /// Opens a place copied with "Copiar link" (a full address or just `/s/...`).
  Future<void> _openLocation(String raw) async {
    final i = raw.indexOf('#');
    final t = _parse(i >= 0 ? raw.substring(i + 1).trim() : raw.trim());
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link não reconhecido.')));
      return;
    }
    // The record opens only once the screen did: leaving a page with unsaved edits asks first, and a "no" keeps everything as it was.
    if (!await _go(t.id, t.filter) || !mounted) return;
    final r = t.record;
    if (r != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRecordByKind(_navContext, widget.session, r.kind, r.id);
      });
    }
  }

  Future<void> _copyLink() async {
    final loc = _location();
    await Clipboard.setData(ClipboardData(text: kIsWeb ? '${Uri.base.origin}/#$loc' : loc));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado')));
  }

  /// Closing the window with unsaved edits asks first.
  Future<AppExitResponse> _onExitRequested() async {
    if (!DiscardGuard.anyDirty || !mounted) return AppExitResponse.exit;
    return await confirmDiscard(context) ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  bool get _pinned => _pins.any((p) => p.id == _current && p.filter == _filter);

  void _togglePin() {
    setState(() {
      if (_pinned) {
        _pins = [
          for (final p in _pins)
            if (!(p.id == _current && p.filter == _filter)) p,
        ];
      } else {
        _pins = [..._pins, (id: _current, filter: _filter)];
      }
    });
    unawaited(_savePins());
  }

  Future<void> _savePins() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('navPins', [for (final x in _pins) '${x.id}\n${x.filter ?? ''}']);
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
    }
  }

  void _onInnerPages() {
    final n = (_innerTrail.pages.value - 1).clamp(0, 99);
    if (mounted && n != _inner) setState(() => _inner = n);
  }

  void _refreshPages() {
    if (mounted) _rev.value++;
  }

  /// Marks a screen as alive. One left for a while, and the Painel, start over so they show fresh data.
  void _mount(String id, String? filter) {
    final k = _key(id, filter);
    final seen = _left[k];
    if (id == 'dashboard' || (seen != null && DateTime.now().difference(seen) > _keepFor)) _mounted.remove(k);
    _mounted.removeWhere((key, t) => key != k && t.id == id);
    _mounted[k] = (id: id, filter: filter);
    while (_mounted.length > _keepMax) {
      _mounted.remove(_mounted.keys.firstWhere((key) => key != k));
    }
  }

  bool _paletteOpen = false;

  static const _digits = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Ctrl+K search, Alt+← / Alt+→ back and forward through visited screens, Ctrl+1…9 the modules, Ctrl+0 the Painel.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) return _onEsc();
    if (e is! KeyDownEvent) return false;
    final k = HardwareKeyboard.instance;
    final free = !_paletteOpen && mounted && (ModalRoute.of(context)?.isCurrent ?? false);
    if (k.isAltPressed && !k.isControlPressed && !k.isShiftPressed && !k.isMetaPressed) {
      if (!free) return false;
      if (e.logicalKey == LogicalKeyboardKey.arrowLeft) return _back();
      if (e.logicalKey == LogicalKeyboardKey.arrowRight) return _forward();
      return false;
    }
    if (!k.isControlPressed) return false;
    if (e.logicalKey == LogicalKeyboardKey.keyK) {
      if (!free) return false;
      _openPalette();
      return true;
    }
    final d = _digits.indexOf(e.logicalKey);
    if (d < 0 || !free || k.isAltPressed || k.isShiftPressed) return false;
    if (d == 0) {
      _go('dashboard');
      return true;
    }
    if (d > modules.length) return false;
    _go(modules[d - 1].id);
    return true;
  }

  /// Esc: leave a text field first, then go back one step (open record, previous screen, Painel).
  bool _onEsc() {
    final k = HardwareKeyboard.instance;
    if (k.isControlPressed || k.isAltPressed || k.isShiftPressed || k.isMetaPressed) return false;
    if (_paletteOpen || !mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      focus!.unfocus();
      return true;
    }
    return _back();
  }

  Future<void> _restorePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _collapsed = p.getBool('navCollapsed') ?? false;
        _pins = [
          for (final raw in p.getStringList('navPins') ?? const <String>[])
            if (_items.any((i) => i.id == raw.split('\n').first))
              (id: raw.split('\n').first, filter: raw.contains('\n') && raw.split('\n').last.isNotEmpty ? raw.split('\n').last : null),
        ];
      });
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('navCollapsed', _collapsed);
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
      // Local storage is best effort; the in-memory value stays.
    }
  }

  /// Goes to a screen from the sidebar, the Painel, the bell or the palette: closes open record pages and remembers where it came from.
  /// False when the user chose to stay (a record page has unsaved edits and the question was answered "no").
  Future<bool> _go(String id, [String? filter]) async {
    final inner = _innerNav;
    if (inner != null && inner.canPop() && DiscardGuard.anyDirty) {
      // popUntil skips PopScope, so ask here before closing a record page with unsaved edits.
      if (!await confirmDiscard(context) || !mounted) return false;
    }
    _goNow(id, filter);
    return true;
  }

  /// Two tabs of one group: moving between them is not a trip, so Back, Esc and Recentes do not count it.
  bool _sameGroup(String a, String b) {
    final g = tabGroupOf(a);
    return g != null && g.has(b);
  }

  void _goNow(String id, String? filter) {
    _innerNav?.popUntil((r) => r.isFirst);
    if (id == _current && filter == _filter) return;
    final tab = _sameGroup(_current, id);
    if (id == 'dashboard') {
      _history.clear();
    } else if (!tab) {
      _history.add((id: _current, filter: _filter));
      if (_history.length > 30) _history.removeAt(0);
    }
    _fwd.clear();
    _show(id, filter, recent: !tab);
  }

  /// Alt+→: a screen undone with Back comes back.
  bool _forward() {
    if (_fwd.isEmpty) return false;
    final t = _fwd.removeLast();
    _history.add((id: _current, filter: _filter));
    _show(t.id, t.filter);
    return true;
  }

  /// One step back: the open record page, else the previous screen, else the Painel. False when there is nowhere to go.
  bool _back() {
    final inner = _innerNav;
    if (inner != null && inner.canPop()) {
      inner.maybePop();
      return true;
    }
    if (_history.isNotEmpty) {
      final t = _history.removeLast();
      _fwd.add((id: _current, filter: _filter));
      _show(t.id, t.filter);
      return true;
    }
    if (_current != 'dashboard') {
      _fwd.add((id: _current, filter: _filter));
      _show('dashboard', null);
      return true;
    }
    return false;
  }

  void _show(String id, String? filter, {bool recent = true}) {
    _left[_key(_current, _filter)] = DateTime.now();
    _mount(id, filter);
    setState(() {
      _current = id;
      _filter = filter;
    });
    _rev.value++;
    _syncLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _activeKey.currentContext;
      if (c != null && c.mounted) unawaited(Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignment: 0.3));
    });
    if (id != 'dashboard' && recent) RecentStore.add(RecentItem('screen', id, _items.firstWhere((i) => i.id == id).title));
  }

  void _openProduct(int id) => openProduct(_navContext, widget.session, id);

  Future<void> _openHit(String group, int id) async {
    final s = widget.session;
    try {
      switch (group) {
        case 'products':
          _openProduct(id);
        case 'production-orders':
          await openProductionOrder(_navContext, s, id);
        case 'sales-orders':
          await openSalesOrder(_navContext, s, id);
        case 'quotes':
          await openQuote(_navContext, s, id);
        case 'customers':
          await openCustomer(_navContext, s, id);
        case 'fiscal-documents':
          await openFiscalDocument(_navContext, s, id);
        case 'certificates':
          await openCertificate(_navContext, s, id);
        case 'suppliers':
          await openSupplier(_navContext, s, id);
        case 'purchase-orders':
          await openPurchaseOrder(_navContext, s, id);
        case 'deliveries':
          await openDelivery(_navContext, s, id);
        default:
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir este resultado.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _openPalette() async {
    _paletteOpen = true;
    try {
      await _showPalette();
    } finally {
      _paletteOpen = false;
    }
  }

  Future<void> _showPalette() => showCommandPalette(
    context,
    session: widget.session,
    // A tab names its group ("Comercial › Expedição") so "Certificados" is not mistaken for a screen of its own.
    targets: [
      for (final i in _items)
        SearchTarget(
          i.id,
          i.icon,
          i.title,
          i.section == hiddenSection ? 'Módulos' : (_shownGroup(i.id) == null ? i.section : '${i.section} › ${tabGroupOf(i.id)!.title}'),
        ),
    ],
    actions: [for (final a in quickActionsFor(widget.session)) PaletteAction(a.icon, a.label, () => a.run(_navContext))],
    onNavigate: _go,
    onOpenHit: _openHit,
    onOpenLink: _openLocation,
  );

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  Widget _railItem(NavItem d, ColorScheme cs, VoidCallback tap, {String? title, IconData? icon, bool? selected}) {
    final active = selected ?? d.id == _current;
    return Tooltip(
      key: active ? _activeKey : null,
      message: title ?? d.title,
      // The collapsed sidebar is icons only: the name and the selection must reach a screen reader, not only the colour.
      child: Semantics(
        button: true,
        selected: active,
        label: title ?? d.title,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: active ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: tap,
              child: SizedBox(height: 40, child: Icon(icon ?? d.icon, color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
            ),
          ),
        ),
      ),
    );
  }

  /// A pinned screen in the collapsed sidebar: a star that opens it, named by its tooltip.
  Widget _railPin(({String id, String? filter}) p, ColorScheme cs, VoidCallback tap) {
    final selected = p.id == _current && p.filter == _filter;
    return Tooltip(
      message: _pinLabel(p),
      child: Semantics(
        button: true,
        selected: selected,
        label: _pinLabel(p),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: selected ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: ValueKey('nav-pin-${p.id}-${p.filter ?? ''}'),
              borderRadius: BorderRadius.circular(10),
              onTap: tap,
              child: SizedBox(height: 40, child: Icon(Icons.star, size: 20, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
            ),
          ),
        ),
      ),
    );
  }

  /// What a pin is called in the sidebar: a tab says its group first ("Expedição · Certificados"), and the filter follows.
  String _pinLabel(({String id, String? filter}) p) {
    final item = _items.firstWhere((i) => i.id == p.id);
    final g = _shownGroup(p.id)?.group;
    final tab = g?.tabLabel(p.id);
    final name = g == null ? item.title : (tab == null ? g.title : '${g.title} · $tab');
    return p.filter == null ? name : '$name · ${p.filter}';
  }

  Widget _tile(NavItem d, ColorScheme cs, VoidCallback tap, {String? title, IconData? icon, bool? selected}) {
    final active = selected ?? d.id == _current;
    return Padding(
      key: active ? _activeKey : null,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: title ?? d.title,
        waitDuration: const Duration(milliseconds: 600),
        child: ListTile(
          key: ValueKey('nav-${d.id}'),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(icon ?? d.icon),
          title: Text(
            title ?? d.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: active ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          selected: active,
          selectedTileColor: cs.secondaryContainer,
          selectedColor: cs.onSecondaryContainer,
          onTap: tap,
        ),
      ),
    );
  }

  String? get _moduleSection => _sectionOf(_current);

  /// The module a screen belongs to, or null for the Painel and the administration screens.
  String? _sectionOf(String id) {
    final item = _items.firstWhere((i) => i.id == id);
    return item.section == hiddenSection ? item.id.substring('module:'.length) : (modules.any((m) => m.section == item.section) ? item.section : null);
  }

  /// Comercial has too many screens for one flat list; the rest of the modules are short enough to stay ungrouped.
  static const _comercialGroups = {
    'Vendas': ['customers', 'sales-pipeline', 'sales-quotes', 'viability', 'sales-orders', 'deliveries', 'certificates', 'fiscal-documents', 'receivables'],
    'Relatórios': ['report-material-consumption', 'report-billing'],
  };

  /// The tab group [id] belongs to and the first of its tabs this user can open; null when fewer than two tabs show.
  ({TabGroup group, String first})? _shownGroup(String id) {
    final g = tabGroupOf(id);
    if (g == null) return null;
    final shown = [
      for (final t in g.tabs)
        if (_items.any((i) => i.id == t.id)) t.id,
    ];
    return shown.length < 2 ? null : (group: g, first: shown.first);
  }

  String? _group(NavItem i) {
    if (i.section != 'Comercial') return null;
    for (final e in _comercialGroups.entries) {
      if (e.value.contains(i.id)) return e.key;
    }
    return 'Preços e regras';
  }

  Widget _groupLabel(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
    ),
  );

  Widget _menu({bool closeDrawer = false, bool rail = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];

    Widget one(NavItem d, {String? title, TabGroup? group}) {
      void tap() {
        _go(d.id);
        if (closeDrawer) Navigator.pop(context);
      }

      final selected = group?.has(_current);
      return rail
          ? _railItem(d, cs, tap, title: group?.title, icon: group?.icon, selected: selected)
          : _tile(d, cs, tap, title: title ?? group?.title, icon: group?.icon, selected: selected);
    }

    final dashboard = _items.firstWhere((i) => i.id == 'dashboard');
    children.add(one(dashboard));
    if (rail && _pins.isNotEmpty) {
      for (final p in _pins) {
        children.add(
          _railPin(p, cs, () {
            _go(p.id, p.filter);
            if (closeDrawer) Navigator.pop(context);
          }),
        );
      }
    }
    if (!rail && _pins.isNotEmpty) {
      children.add(_groupLabel('Fixados', theme));
      for (final p in _pins) {
        final label = _pinLabel(p);
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              key: ValueKey('nav-pin-${p.id}-${p.filter ?? ''}'),
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.star, size: 20),
              title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
              selected: p.id == _current && p.filter == _filter,
              selectedTileColor: cs.secondaryContainer,
              selectedColor: cs.onSecondaryContainer,
              onTap: () {
                _go(p.id, p.filter);
                if (closeDrawer) Navigator.pop(context);
              },
            ),
          ),
        );
      }
    }
    if (closeDrawer) children.add(_recents(theme));
    final current = _moduleSection;

    void moduleItems(String section) {
      String? lastGroup;
      for (final i in _items.where((i) => i.section == section)) {
        final tg = _shownGroup(i.id);
        // Only the first tab of a group has a sidebar entry; the others are reached from the tabs on the screen.
        if (tg != null && tg.first != i.id) continue;
        final g = _group(i);
        // A label that only repeats the title of the one entry under it ("Relatórios" over "Relatórios") says nothing.
        final repeats = tg != null && tg.group.title == g;
        if (g != null && g != lastGroup) {
          if (rail) {
            children.add(const Divider(indent: 16, endIndent: 16));
          } else {
            children.add(repeats ? const Divider(indent: 16, endIndent: 16, height: 16) : _groupLabel(g, theme));
          }
        }
        lastGroup = g;
        children.add(one(i, group: tg?.group));
      }
    }

    for (final m in modules) {
      final home = _items.firstWhere((i) => i.id == m.id);
      final isCurrent = m.section == current;
      if (current != null && !isCurrent) continue;
      if (rail) {
        // A module is one icon that opens its overview; the module being worked in lists its screens under it.
        if (isCurrent) children.add(const Divider());
        children.add(one(home));
        if (isCurrent) {
          moduleItems(m.section);
          children.add(const Divider());
        }
        continue;
      }
      // On the Painel the modules are the way in; inside one, only that module's screens are listed.
      if (!isCurrent) {
        children.add(one(home, title: m.section));
        continue;
      }
      // The module name opens its overview.
      children.add(
        Padding(
          key: ValueKey('nav-section-${m.section}'),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
          child: Tooltip(
            message: 'Visão geral de ${m.section}',
            child: ListTile(
              key: ValueKey('nav-${home.id}'),
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: Icon(m.icon, color: cs.primary),
              title: Text(m.section, style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              selected: _current == home.id,
              selectedTileColor: cs.secondaryContainer,
              onTap: () {
                _go(home.id);
                if (closeDrawer) Navigator.pop(context);
              },
            ),
          ),
        ),
      );
      moduleItems(m.section);
      // Inside a module only its screens are listed; the other modules are one tap away without going through the Painel.
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('nav-switch-module'),
              dense: true,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.swap_horiz),
              title: Text('Trocar de módulo', style: theme.textTheme.bodyMedium),
              children: [
                for (final o in modules)
                  if (o.section != m.section) one(_items.firstWhere((i) => i.id == o.id), title: o.section),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);
  }

  /// Phone drawer: the last screens and records the user opened.
  Widget _recents(ThemeData theme) => FutureBuilder<List<RecentItem>>(
    future: RecentStore.load(),
    builder: (_, snap) {
      final list = [
        for (final r in snap.data ?? const <RecentItem>[])
          if (r.type != 'screen' || _items.any((i) => i.id == r.id)) r,
      ].take(4).toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupLabel('Recentes', theme),
          for (final r in list)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                if (r.type == 'screen') {
                  _go(r.id);
                } else {
                  unawaited(_openHit(r.type, int.tryParse(r.id) ?? 0));
                }
              },
            ),
        ],
      );
    },
  );

  /// Where the screen sits: `Módulo › Tela`, and for a tab of a group `Módulo › Grupo › Aba` — the names the sidebar and the tab strip show.
  String _crumb() {
    final item = _item;
    if (_moduleSection == null || item.section == hiddenSection) return item.title;
    final g = _shownGroup(item.id)?.group;
    if (g == null) return '${item.section} › ${item.title}';
    final tab = g.tabLabel(item.id);
    return tab == null ? '${item.section} › ${g.title}' : '${item.section} › ${g.title} › $tab';
  }

  /// Breadcrumb in the app bar: the module and screen, then every record page open over it (wide layout). Each step but the last goes back to it.
  Widget _title(bool wide) {
    final theme = Theme.of(context);
    final base = _crumb();
    final recs = wide ? _records : const <String>[];
    if (recs.isEmpty) return Text(base, overflow: TextOverflow.ellipsis);
    Widget crumb(String text, VoidCallback? tap) => tap == null
        ? Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          )
        : InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          );
    return Row(
      children: [
        Flexible(child: crumb(base, () => unawaited(_popTo(null)))),
        for (var i = 0; i < recs.length; i++) ...[
          const Icon(Icons.chevron_right, size: 18),
          Flexible(child: crumb(recordLabels[recs[i].split(':')[1]] ?? recs[i], i == recs.length - 1 ? null : () => unawaited(_popTo(recs[i])))),
        ],
      ],
    );
  }

  /// Closes record pages down to the one named [name] (null: all of them), asking first when one has unsaved edits.
  Future<void> _popTo(String? name) async {
    final inner = _innerNav;
    if (inner == null) return;
    if (DiscardGuard.anyDirty && !await confirmDiscard(context)) return;
    if (mounted) inner.popUntil((r) => name == null ? r.isFirst : r.settings.name == name);
  }

  Future<void> _step(int delta) async {
    final inner = _innerNav, top = _top;
    if (inner == null || top == null) return;
    if (DiscardGuard.anyDirty && !await confirmDiscard(context)) return;
    if (mounted) stepRecord(inner, widget.session, top, delta);
  }

  /// Previous / next record of the list the open record page was opened from.
  List<Widget> _stepButtons() {
    final top = _top;
    if (top == null || _records.isEmpty || top.index < 0 || (top.siblings?.length ?? 0) < 2) return const [];
    final n = top.siblings!.length;
    return [
      IconButton(tooltip: 'Registro anterior', onPressed: top.index > 0 ? () => unawaited(_step(-1)) : null, icon: const Icon(Icons.keyboard_arrow_up)),
      Text('${top.index + 1}/$n', style: Theme.of(context).textTheme.labelMedium),
      IconButton(tooltip: 'Próximo registro', onPressed: top.index < n - 1 ? () => unawaited(_step(1)) : null, icon: const Icon(Icons.keyboard_arrow_down)),
      const SizedBox(width: 4),
    ];
  }

  void _showAlerts() => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<List<AlertInfo>>(
        valueListenable: widget.session.alerts,
        builder: (_, list, _) => ListView(
          shrinkWrap: true,
          children: list.isEmpty
              ? [const ListTile(title: Text('Nenhum alerta'))]
              : [
                  for (final a in list)
                    ListTile(
                      leading: Icon(a.icon, color: Theme.of(ctx).colorScheme.error),
                      title: Text(a.label),
                      trailing: Text('${a.count}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _go(a.navId, a.filter);
                      },
                    ),
                ],
        ),
      ),
    ),
  );

  Widget _barButton(IconData icon, String label, VoidCallback onTap, {bool active = false, int badge = 0}) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Expanded(
      // Colour alone does not say which button is current, and a bare badge number does not say what it counts.
      child: Semantics(
        button: true,
        selected: active,
        label: badge > 0 ? '$label, $badge ${badge == 1 ? 'pendente' : 'pendentes'}' : label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: Icon(icon, color: color, size: 22),
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  /// Phone: the four things reached most, always one tap away.
  Widget _bottomBar() => BottomAppBar(
    height: 56,
    padding: EdgeInsets.zero,
    child: Row(
      children: [
        _barButton(Icons.home_outlined, 'Início', () => _go('dashboard'), active: _current == 'dashboard'),
        _barButton(Icons.search, 'Buscar', _openPalette),
        ValueListenableBuilder<List<AlertInfo>>(
          valueListenable: widget.session.alerts,
          builder: (_, _, _) => Expanded(
            child: Row(children: [_barButton(Icons.notifications_none, 'Alertas', _showAlerts, badge: widget.session.alerts.total)]),
          ),
        ),
        _barButton(Icons.apps, 'Menu', () => _scaffoldKey.currentState?.openDrawer()),
      ],
    ),
  );

  Widget _pages() {
    final s = widget.session;
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        for (final e in _mounted.entries)
          _PageSlot(
            key: ValueKey(e.key),
            active: e.key == _key(_current, _filter),
            child: _items.firstWhere((i) => i.id == e.value.id).build(s, e.value.filter, _go),
          ),
      ],
    );
    // One strip above the pages, not one inside each (it would fade and lose its scroll with the page). The column keeps the same two
    // children whether a strip shows or not, so moving to a screen without tabs does not rebuild the pages kept alive.
    final g = _shownGroup(_current)?.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g == null)
          const SizedBox.shrink()
        else
          TabStrip(
            key: ValueKey('tabs-${g.title}'),
            tabs: [
              for (final t in g.tabs)
                if (_items.any((i) => i.id == t.id)) t,
            ],
            current: _current,
            onSelect: _go,
          ),
        Expanded(child: stack),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = widget.session;
    // Wide: record pages open inside the content area, under the sidebar. Narrow: they cover the whole screen.
    final page = wide
        ? HeroControllerScope(
            controller: _hero,
            child: Navigator(
              key: _innerKey,
              observers: [_innerTrail],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => ListenableBuilder(listenable: _rev, builder: (_, _) => _pages()),
              ),
            ),
          )
        : _pages();
    // Back (Android, browser) steps back through open records and visited screens before leaving the app.
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: _scaffoldKey,
        bottomNavigationBar: wide ? null : _bottomBar(),
        appBar: AppBar(
          // On a phone the bottom bar already has Menu, Buscar and Alertas; repeating them here leaves the title 40 dp on a 360 dp screen.
          automaticallyImplyLeading: false,
          leading: wide
              ? IconButton(
                  tooltip: _collapsed ? 'Expandir menu' : 'Recolher menu',
                  onPressed: _toggleCollapsed,
                  icon: Icon(_collapsed ? Icons.menu : Icons.menu_open),
                )
              : null,
          title: Row(
            children: [
              if (_canBack)
                IconButton(tooltip: _inner > 0 || _history.isNotEmpty ? 'Voltar' : 'Voltar ao Painel', onPressed: _back, icon: const Icon(Icons.arrow_back)),
              Flexible(child: _title(wide)),
            ],
          ),
          actions: [
            if (wide) ..._stepButtons(),
            if (_current != 'dashboard')
              IconButton(
                key: const ValueKey('pin-screen'),
                tooltip: _pinned ? 'Desafixar esta tela' : 'Fixar esta tela',
                onPressed: _togglePin,
                icon: Icon(_pinned ? Icons.star : Icons.star_border),
              ),
            if (wide) IconButton(key: const ValueKey('copy-link'), tooltip: 'Copiar link', onPressed: _copyLink, icon: const Icon(Icons.copy_all_outlined)),
            if (wide) ...[
              SearchLauncher(onOpen: _openPalette),
              const SizedBox(width: 4),
              AlertBell(center: s.alerts, onNavigate: _go),
              const SizedBox(width: 12),
            ],
            UserMenu(
              session: s,
              adminScreens: [
                for (final i in _items)
                  if (i.section == 'Sistema') (id: i.id, icon: i.icon, title: i.title),
              ],
              onOpenScreen: _go,
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: wide ? null : Drawer(child: SafeArea(child: _menu(closeDrawer: true))),
        body: wide
            ? Row(
                children: [
                  SizedBox(
                    width: _collapsed ? 72 : 280,
                    child: _menu(rail: _collapsed),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              )
            : page,
      ),
    );
  }
}

/// Keeps a visited screen alive while another one shows: hidden, with no tickers, heroes or focus, and a short fade when it returns.
class _PageSlot extends StatefulWidget {
  const _PageSlot({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_PageSlot> createState() => _PageSlotState();
}

class _PageSlotState extends State<_PageSlot> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 160), value: 1);
  bool _first = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _first = false;
      if (widget.active && !MediaQuery.disableAnimationsOf(context)) _fade.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_PageSlot old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !MediaQuery.disableAnimationsOf(context)) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.active,
    child: TickerMode(
      enabled: widget.active,
      child: HeroMode(
        enabled: widget.active,
        child: ExcludeFocus(
          excluding: !widget.active,
          child: FadeTransition(opacity: _fade, child: widget.child),
        ),
      ),
    ),
  );
}
