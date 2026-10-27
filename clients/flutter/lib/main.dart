import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login.dart';
import 'screens/shell.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  await session.restore();
  runApp(EbtApp(session: session));
}

class EbtApp extends StatelessWidget {
  const EbtApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => MaterialApp(
        title: 'SiderGest',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: session.themeMode,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: session.loggedIn ? Shell(key: ValueKey(session.username), session: session) : LoginScreen(session: session),
      ),
    );
  }
}

ThemeData appTheme(Brightness brightness) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF1F5F99), brightness: brightness);
  return ThemeData(
    colorScheme: cs,
    visualDensity: VisualDensity.compact,
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
