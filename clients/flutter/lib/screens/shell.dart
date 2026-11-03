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

List<NavItem> navItems() {
  final base = _screens();
  final links = {
    for (final m in modules) m.section: [for (final i in base.where((i) => i.section == m.section)) ModuleLink(i.id, i.icon, i.title)],
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
  NavItem('sales-orders', Icons.receipt_long_outlined, 'Pedidos de venda', 'Comercial', (s, f, go) => SalesOrdersScreen(session: s)),
  NavItem('deliveries', Icons.local_shipping_outlined, 'Entregas', 'Comercial', (s, f, go) => DeliveriesScreen(session: s)),
  NavItem('certificates', Icons.verified_outlined, 'Certificados de qualidade', 'Comercial', (s, f, go) => CertificatesScreen(session: s)),
  NavItem('fiscal-documents', Icons.description_outlined, 'Notas fiscais', 'Comercial', (s, f, go) => FiscalDocumentsScreen(session: s)),
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
  static final lastLocation = Expando<({String path, DateTime at})>('lastLocation');

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
  static const _keepMax = 8;

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
  final _open = <String>{};
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
    final section = _sectionOf(_current);
    if (section != null) _open.add(section);
    _restorePrefs();
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
  String _location() {
    final r = _top;
    return Uri(path: '/s/$_current${_records.isNotEmpty && r != null ? r.path : ''}', queryParameters: _filter == null ? null : {'f': _filter}).toString();
  }

  void _syncLocation() {
    final loc = _location();
    Shell.lastLocation[widget.session] = (path: loc, at: DateTime.now());
    if (kIsWeb) unawaited(SystemNavigator.routeInformationUpdated(uri: Uri.parse(loc), replace: true));
  }

  /// Where to open: the address the browser was loaded with, else the place this user left less than 30 minutes ago.
  ({String id, String? filter, ({String kind, int id})? record})? _startLocation() {
    final fromWeb = kIsWeb ? WidgetsBinding.instance.platformDispatcher.defaultRouteName : null;
    final seen = Shell.lastLocation[widget.session];
    final path = fromWeb != null && fromWeb.startsWith('/s/')
        ? fromWeb
        : (seen != null && DateTime.now().difference(seen.at) < const Duration(minutes: 30) ? seen.path : null);
    return path == null ? null : _parse(path);
  }

  ({String id, String? filter, ({String kind, int id})? record})? _parse(String path) {
    final uri = Uri.tryParse(path);
    final m = uri == null ? null : RegExp(r'^/s/([^/]+)(?:/r/([^/]+)/(\d+))?$').firstMatch(uri.path);
    if (m == null || !_items.any((i) => i.id == m[1])) return null;
    final kind = m[2], rid = int.tryParse(m[3] ?? '');
    return (id: m[1]!, filter: uri!.queryParameters['f'], record: kind != null && rid != null ? (kind: kind, id: rid) : null);
  }

  /// Opens a place copied with "Copiar link" (a full address or just `/s/...`).
  void _openLocation(String raw) {
    final i = raw.indexOf('#');
    final t = _parse(i >= 0 ? raw.substring(i + 1).trim() : raw.trim());
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link não reconhecido.')));
      return;
    }
    _go(t.id, t.filter);
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
        _open.addAll(p.getStringList('navOpen') ?? const []);
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
  void _go(String id, [String? filter]) {
    final inner = _innerNav;
    if (inner != null && inner.canPop() && DiscardGuard.anyDirty) {
      // popUntil skips PopScope, so ask here before closing a record page with unsaved edits.
      unawaited(
        confirmDiscard(context).then((ok) {
          if (ok && mounted) _goNow(id, filter);
        }),
      );
      return;
    }
    _goNow(id, filter);
  }

  void _goNow(String id, String? filter) {
    _innerNav?.popUntil((r) => r.isFirst);
    if (id == _current && filter == _filter) return;
    if (id == 'dashboard') {
      _history.clear();
    } else {
      _history.add((id: _current, filter: _filter));
      if (_history.length > 30) _history.removeAt(0);
    }
    _fwd.clear();
    _show(id, filter);
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

  void _show(String id, String? filter) {
    _left[_key(_current, _filter)] = DateTime.now();
    _mount(id, filter);
    final section = _sectionOf(id);
    setState(() {
      _current = id;
      _filter = filter;
      if (section != null) _open.add(section);
    });
    _rev.value++;
    _syncLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _activeKey.currentContext;
      if (c != null && c.mounted) unawaited(Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignment: 0.3));
    });
    if (id != 'dashboard') RecentStore.add(RecentItem('screen', id, _items.firstWhere((i) => i.id == id).title));
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
    targets: [for (final i in _items) SearchTarget(i.id, i.icon, i.title, i.section == hiddenSection ? 'Módulos' : i.section)],
    actions: [for (final a in quickActionsFor(widget.session)) PaletteAction(a.icon, a.label, () => a.run(_navContext))],
    onNavigate: _go,
    onOpenHit: _openHit,
    onOpenLink: _openLocation,
  );

  NavItem get _item => _items.firstWhere((i) => i.id == _current);

  Widget _railItem(NavItem d, ColorScheme cs, VoidCallback tap) {
    final active = d.id == _current;
    return Tooltip(
      key: active ? _activeKey : null,
      message: d.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: active ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: tap,
            child: SizedBox(height: 40, child: Icon(d.icon, color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }

  Widget _tile(NavItem d, ColorScheme cs, VoidCallback tap, {String? title}) {
    final active = d.id == _current;
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
          leading: Icon(d.icon),
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
    'Vendas': ['customers', 'sales-pipeline', 'sales-quotes', 'viability', 'sales-orders', 'deliveries'],
    'Fiscal e qualidade': ['certificates', 'fiscal-documents'],
    'Relatórios': ['report-material-consumption', 'report-billing'],
  };

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

    Widget one(NavItem d, {String? title}) {
      void tap() {
        _go(d.id);
        if (closeDrawer) Navigator.pop(context);
      }

      return rail ? _railItem(d, cs, tap) : _tile(d, cs, tap, title: title);
    }

    final dashboard = _items.firstWhere((i) => i.id == 'dashboard');
    children.add(one(dashboard));
    if (!rail && _pins.isNotEmpty) {
      children.add(_groupLabel('Fixados', theme));
      for (final p in _pins) {
        final item = _items.firstWhere((i) => i.id == p.id);
        final label = p.filter == null ? item.title : '${item.title} · ${p.filter}';
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
        final g = _group(i);
        if (g != null && g != lastGroup) children.add(rail ? const Divider(indent: 16, endIndent: 16) : _groupLabel(g, theme));
        lastGroup = g;
        children.add(one(i));
      }
    }

    for (final m in modules) {
      final home = _items.firstWhere((i) => i.id == m.id);
      final isCurrent = m.section == current;
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
      final open = _open.contains(m.section);
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListTile(
            key: ValueKey('nav-section-${m.section}'),
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(m.icon, color: isCurrent ? cs.primary : null),
            title: Text(
              m.section,
              style: theme.textTheme.labelLarge?.copyWith(color: isCurrent ? cs.primary : null, fontWeight: FontWeight.w700),
            ),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: () => _toggleSection(m.section),
          ),
        ),
      );
      if (open) {
        children.add(one(home, title: 'Visão geral'));
        moduleItems(m.section);
      }
    }
    final system = _items.where((i) => i.section == 'Sistema');
    if (system.isNotEmpty) {
      children.add(const Divider());
      if (!rail) children.add(_groupLabel('Administração', theme));
      children.addAll(system.map(one));
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

  void _toggleSection(String section) {
    setState(() => _open.contains(section) ? _open.remove(section) : _open.add(section));
    unawaited(_saveOpen());
  }

  Future<void> _saveOpen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('navOpen', _open.toList());
    } catch (e) {
      debugPrint('shell: Local storage is best effort; the in-memory value stays: $e');
    }
  }

  /// Breadcrumb in the app bar: the module and screen, then every record page open over it (wide layout). Each step but the last goes back to it.
  Widget _title(bool wide) {
    final theme = Theme.of(context);
    final base = _moduleSection == null || _item.section == hiddenSection ? _item.title : '${_item.section} › ${_item.title}';
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
    return Stack(
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
            SearchLauncher(onOpen: _openPalette, compact: !wide),
            const SizedBox(width: 4),
            AlertBell(center: s.alerts, onNavigate: _go),
            const SizedBox(width: 12),
            UserMenu(session: s),
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
