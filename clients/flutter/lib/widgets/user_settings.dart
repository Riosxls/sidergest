import 'package:flutter/material.dart';

import '../api.dart';
import '../screens/data_reset.dart';
import '../session.dart';
import 'command_palette.dart';
import 'record_list.dart';

/// Personal preferences of the signed-in user on this device (not the system parameters under Parâmetros).
Future<void> showUserSettings(BuildContext context, Session session) => showDialog<void>(context: context, builder: (_) => _UserSettings(session: session));

/// Minimum length the server enforces for passwords.
const minPasswordLength = 10;

/// Forgets what the app keeps locally to speed things up: loaded names, recent searches and record versions.
/// Server data and the login are not touched.
Future<void> clearLocalCache(Session session) async {
  NameCache.clear();
  session.api.clearVersions();
  await RecentStore.clear();
}

class _UserSettings extends StatelessWidget {
  const _UserSettings({required this.session});

  final Session session;

  Future<void> _clearCache(BuildContext context) async {
    await clearLocalCache(session);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache do aplicativo limpo')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return AlertDialog(
      title: const Text('Configurações'),
      content: SizedBox(
        width: 480,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aparência', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  key: const ValueKey('settings-theme'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Escuro')),
                  ],
                  selected: {session.themeMode},
                  onSelectionChanged: (s) => session.setThemeMode(s.first),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  key: const ValueKey('settings-density'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.density_small), label: Text('Compacto')),
                    ButtonSegment(value: true, icon: Icon(Icons.density_medium), label: Text('Confortável')),
                  ],
                  selected: {session.comfortable},
                  onSelectionChanged: (s) => session.setComfortable(s.first),
                ),
                const SizedBox(height: 12),
                SegmentedButton<double>(
                  key: const ValueKey('settings-text-size'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('Texto normal')),
                    ButtonSegment(value: 1.15, label: Text('Grande')),
                    ButtonSegment(value: 1.3, label: Text('Maior')),
                  ],
                  selected: {session.textScale},
                  onSelectionChanged: (s) => session.setTextScale(s.first),
                ),
                title('Sessão'),
                SwitchListTile(
                  key: const ValueKey('settings-remember'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Manter conectado neste dispositivo'),
                  subtitle: Text(session.remember ? 'Você continua conectado ao reabrir o aplicativo' : 'A sessão termina ao fechar o aplicativo'),
                  value: session.remember,
                  onChanged: session.setRemember,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('settings-change-password'),
                  onPressed: () => showChangePassword(context, session),
                  icon: const Icon(Icons.password_outlined),
                  label: const Text('Alterar minha senha…'),
                ),
                title('Dados do aplicativo'),
                const Text('Limpa os nomes e as buscas recentes guardados neste dispositivo. Seus dados no servidor e o login não mudam.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('settings-clear-cache'),
                  onPressed: () => _clearCache(context),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpar cache do aplicativo'),
                ),
                title('Servidor'),
                SelectableText(session.baseUrl),
                if (session.isAdmin) ...[
                  title('Administração'),
                  const Text(
                    'Apaga orçamentos, pedidos, entregas, ordens de fabricação e outros registros do dia a dia para recomeçar do zero. '
                    'Produtos, materiais, clientes, fornecedores, ferramentas e preços ficam como estão.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('open-data-reset'),
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => showDataResetDialog(context, session),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpar dados de movimento…'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

Future<void> showChangePassword(BuildContext context, Session session) => showDialog<void>(context: context, builder: (_) => _ChangePassword(session: session));

class _ChangePassword extends StatefulWidget {
  const _ChangePassword({required this.session});

  final Session session;

  @override
  State<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<_ChangePassword> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_current.text.isEmpty) return 'Informe a senha atual';
    if (_next.text.length < minPasswordLength) return 'A nova senha precisa ter pelo menos $minPasswordLength caracteres';
    if (_next.text == _current.text) return 'A nova senha precisa ser diferente da atual';
    if (_next.text != _again.text) return 'A confirmação não é igual à nova senha';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada. Os outros dispositivos foram desconectados.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(Key key, TextEditingController c, String label, {bool last = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key,
      controller: c,
      obscureText: !_show,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _save() : null,
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Alterar minha senha'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(const ValueKey('pw-current'), _current, 'Senha atual'),
              _field(const ValueKey('pw-new'), _next, 'Nova senha (mínimo $minPasswordLength caracteres)'),
              _field(const ValueKey('pw-again'), _again, 'Repita a nova senha', last: true),
              CheckboxListTile(
                key: const ValueKey('pw-show'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _show,
                onChanged: (v) => setState(() => _show = v ?? false),
                title: const Text('Mostrar senhas'),
              ),
              const Text('Ao trocar a senha, você continua conectado aqui e é desconectado dos outros dispositivos.'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: cs.error))),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('pw-save'), onPressed: _busy ? null : _save, child: const Text('Alterar senha')),
      ],
    );
  }
}
