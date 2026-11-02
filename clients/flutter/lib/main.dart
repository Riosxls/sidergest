import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login.dart';
import 'screens/shell.dart';
import 'session.dart';
import 'widgets/app_text_scale.dart';
import 'widgets/esc_back.dart';
import 'widgets/idle_guard.dart';
import 'widgets/record_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  await session.restore();
  runApp(EbtApp(session: session));
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

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = session.loggedIn;
    session.addListener(_closeScreensOnSignOut);
  }

  @override
  void dispose() {
    session.removeListener(_closeScreensOnSignOut);
    super.dispose();
  }

  /// Signing out (idle lock, expired session, manual) must not leave a pushed screen or dialog open over the login page.
  void _closeScreensOnSignOut() {
    final now = session.loggedIn;
    if (_wasLoggedIn && !now) _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _wasLoggedIn = now;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => MaterialApp(
        title: 'MetaGest',
        navigatorKey: _navigatorKey,
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

ThemeData appTheme(Brightness brightness, {bool comfortable = false, bool highContrast = false, bool reduceMotion = false}) {
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
  );
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
