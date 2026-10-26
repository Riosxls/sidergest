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
    return MaterialApp(
      title: 'SiderGest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F5F99), visualDensity: VisualDensity.compact),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1F5F99), brightness: Brightness.dark, visualDensity: VisualDensity.compact),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: session,
        builder: (_, _) => session.loggedIn ? Shell(key: ValueKey(session.username), session: session) : LoginScreen(session: session),
      ),
    );
  }
}
