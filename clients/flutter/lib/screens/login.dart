import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _url = TextEditingController(text: widget.session.baseUrl);
  final _user = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showServer = false;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) return setState(() => _error = 'Informe usuário e senha');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_url.text, _user.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.precision_manufacturing, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('SiderGest', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextField(
                    key: const ValueKey('login-user'),
                    controller: _user,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Usuário', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('login-password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline), border: OutlineInputBorder()),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_showServer) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('login-url'),
                      controller: _url,
                      decoration: const InputDecoration(labelText: 'Servidor da API', prefixIcon: Icon(Icons.dns_outlined), border: OutlineInputBorder()),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showServer = !_showServer),
                    child: Text('Servidor: ${_url.text}', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
