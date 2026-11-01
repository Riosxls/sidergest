import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import 'command_palette.dart';
import 'record_list.dart';

/// Minimum length the server enforces for passwords.
const minPasswordLength = 10;

/// Forgets what the app keeps locally to speed things up: loaded names, recent searches and record versions.
/// Server data and the login are not touched.
Future<void> clearLocalCache(Session session) async {
  NameCache.clear();
  session.api.clearVersions();
  await RecentStore.clear();
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
