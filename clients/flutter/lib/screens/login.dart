import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final _user = TextEditingController(text: widget.session.lastUser);
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;
  bool _busy = false;
  bool _showServer = false;
  bool _showPassword = false;
  bool _capsLock = false;
  late bool _remember = widget.session.remember;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _passwordFocus.dispose();
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    final caps = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (caps != _capsLock && mounted) setState(() => _capsLock = caps);
    return false;
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  String _message(ApiException e) {
    if (e.status == 401) {
      return _failures >= 3
          ? 'Usuário ou senha inválidos. Depois de várias tentativas o acesso é bloqueado por 15 minutos.'
          : 'Usuário ou senha inválidos';
    }
    if (e.status == 429) return 'Muitas tentativas seguidas. Aguarde um minuto e tente de novo.';
    return e.message;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _password.text.isEmpty) return setState(() => _error = 'Informe usuário e senha');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_url.text, _user.text.trim(), _password.text, remember: _remember);
      TextInput.finishAutofillContext();
    } on ApiException catch (e) {
      _failures += e.status == 401 ? 1 : 0;
      if (mounted) {
        setState(() {
          _error = _message(e);
          // Server unreachable: reveal the address so it can be corrected.
          if (e.status == 0) _showServer = true;
        });
        if (e.status == 401) {
          _password.selection = TextSelection(baseOffset: 0, extentOffset: _password.text.length);
          _passwordFocus.requestFocus();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                  Icon(Icons.precision_manufacturing, size: 56, color: cs.primary),
                  const SizedBox(height: 8),
                  Text('SiderGest', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextField(
                    key: const ValueKey('login-user'),
                    controller: _user,
                    autofocus: widget.session.lastUser.isEmpty,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearError(),
                    decoration: const InputDecoration(labelText: 'Usuário', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('login-password'),
                    controller: _password,
                    focusNode: _passwordFocus,
                    autofocus: widget.session.lastUser.isNotEmpty,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _clearError(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        key: const ValueKey('login-toggle-password'),
                        tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                        icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_capsLock)
                    Padding(
                      key: const ValueKey('login-caps-lock'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Icon(Icons.keyboard_capslock, size: 16, color: cs.tertiary),
                          const SizedBox(width: 6),
                          Text('Caps Lock está ligado', style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    key: const ValueKey('login-remember'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? true),
                    title: const Text('Lembrar de mim neste dispositivo'),
                    subtitle: _remember ? null : const Text('A sessão termina ao fechar o aplicativo'),
                  ),
                  if (_showServer) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('login-url'),
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Servidor da API', prefixIcon: Icon(Icons.dns_outlined), border: OutlineInputBorder()),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, size: 18, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_error!, style: TextStyle(color: cs.error))),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showServer = !_showServer),
                    child: Text(_showServer ? 'Ocultar servidor' : 'Servidor: ${_url.text}', overflow: TextOverflow.ellipsis),
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
