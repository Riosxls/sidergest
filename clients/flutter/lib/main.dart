import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login.dart';
import 'screens/shell.dart';
import 'session.dart';
import 'theme_tokens.dart';
import 'widgets/app_text_scale.dart';
import 'widgets/drafts.dart';
import 'widgets/esc_back.dart';
import 'widgets/idle_guard.dart';
import 'widgets/pipeline.dart' show StatusColors;
import 'widgets/record_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  // Local storage only: the app shows at once with the stored session and permissions; the server refresh (token, role, permissions) follows in the background.
  await session.restoreLocal();
  runApp(EbtApp(session: session));
  unawaited(session.refreshRemote());
}

/// Root widget: wires the session, theme and the login/shell navigation.
class EbtApp extends StatefulWidget {
  const EbtApp({super.key, required this.session});

  final Session session;

  @override
  State<EbtApp> createState() => _EbtAppState();
}

class _EbtAppState extends State<EbtApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _escObserver = EscRouteObserver();
  final _trail = RecordTrail();
  bool _wasLoggedIn = false;
  late _Appearance _appearance;

  Session get session => widget.session;

  _Appearance _readAppearance() => (
    themeMode: session.themeMode,
    comfortable: session.comfortable,
    highContrast: session.highContrast,
    reduceMotion: session.reduceMotion,
    textScale: session.textScale,
    loggedIn: session.loggedIn,
    username: session.username,
  );

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = session.loggedIn;
    _appearance = _readAppearance();
    session.addListener(_closeScreensOnSignOut);
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_closeScreensOnSignOut);
    session.removeListener(_onSession);
    super.dispose();
  }

  /// The session notifies for many reasons (permissions, idle settings, tokens); MaterialApp only rebuilds when something it shows changed.
  void _onSession() {
    final now = _readAppearance();
    if (now != _appearance) setState(() => _appearance = now);
  }

  /// Signing out (idle lock, expired session, manual) must not leave a pushed screen or dialog open over the login page.
  void _closeScreensOnSignOut() {
    final now = session.loggedIn;
    if (_wasLoggedIn && !now) {
      DraftRegistry.saveAll();
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    _wasLoggedIn = now;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (_) => MaterialApp(
        title: 'MetaGest',
        navigatorKey: _navigatorKey,
        initialRoute: '/',
        navigatorObservers: [_escObserver, _trail],
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light, comfortable: session.comfortable, highContrast: session.highContrast, reduceMotion: session.reduceMotion),
        darkTheme: appTheme(Brightness.dark, comfortable: session.comfortable, highContrast: session.highContrast, reduceMotion: session.reduceMotion),
        builder: (context, child) => EscBack(
          navigatorKey: _navigatorKey,
          observer: _escObserver,
          child: IdleGuard(
          session: session,
          navigatorKey: _navigatorKey,
          child: AppTextScale(
            factor: session.textScale,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: session.reduceMotion || MediaQuery.of(context).disableAnimations),
              child: child!,
            ),
          ),
        ),
        ),
        themeMode: session.themeMode,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: session.loggedIn ? Shell(key: ValueKey(session.username), session: session) : LoginScreen(session: session),
      ),
    );
  }
}

/// What [MaterialApp] shows that comes from the session; the app rebuilds only when this changes.
typedef _Appearance = ({
  ThemeMode themeMode,
  bool comfortable,
  bool highContrast,
  bool reduceMotion,
  double textScale,
  bool loggedIn,
  String? username,
});

final _themeCache = <(Brightness, bool, bool, bool), ThemeData>{};

/// The app theme; one instance per combination of brightness, density, contrast and motion, so repeated builds reuse it.
ThemeData appTheme(Brightness brightness, {bool comfortable = false, bool highContrast = false, bool reduceMotion = false}) =>
    _themeCache.putIfAbsent((brightness, comfortable, highContrast, reduceMotion), () => _buildTheme(brightness, comfortable, highContrast, reduceMotion));

ThemeData _buildTheme(Brightness brightness, bool comfortable, bool highContrast, bool reduceMotion) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF1F5F99), brightness: brightness, contrastLevel: highContrast ? 1.0 : 0.0);
  return ThemeData(
    colorScheme: cs,
    visualDensity: comfortable ? VisualDensity.standard : VisualDensity.compact,
    pageTransitionsTheme: reduceMotion
        ? PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const _NoTransitions()})
        : null,
    cardTheme: CardThemeData(
      color: cs.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        // High contrast: a stronger border so cards stay separated from the page.
        side: BorderSide(color: highContrast ? cs.outline : cs.outlineVariant),
      ),
    ),
    // Outlined fields everywhere; screens that need compact fields still pass isDense.
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    extensions: [StatusColors.build(cs, highContrast: highContrast)],
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card + 4)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      side: BorderSide(color: cs.outlineVariant),
    ),
    listTileTheme: ListTileThemeData(iconColor: cs.onSurfaceVariant),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // A visible ring on keyboard focus for every button, so Tab navigation shows where it is.
    focusColor: cs.primary.withValues(alpha: 0.18),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: _focusRing(cs))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: _focusRing(cs, base: cs.outline))),
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: _focusRing(cs))),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: _focusRing(cs))),
  );
}

/// Border that turns into a 2 px primary ring while the button has keyboard focus.
WidgetStateProperty<BorderSide?> _focusRing(ColorScheme cs, {Color? base}) => WidgetStateProperty.resolveWith((states) {
  if (states.contains(WidgetState.focused)) return BorderSide(color: cs.primary, width: 2);
  return base == null ? null : BorderSide(color: base);
});

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
