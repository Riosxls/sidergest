/// Personal preferences that widgets without a [Session] in reach read directly; [Session] keeps them in step with what is saved.
class AppPrefs {
  /// Rows per page in lists that do not ask for a fixed size.
  static int rowsPerPage = 50;

  /// When false the flow never stops to ask for a print or download (see `printGate`).
  static bool printPrompts = true;

  static const rowsPerPageChoices = [25, 50, 100];
}

/// Shown under Configurações > Sobre. Release builds pass `--dart-define=APP_VERSION=...`.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
