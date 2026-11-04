import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/load_error.dart';
import '../widgets/page_column.dart';
import '../widgets/pipeline.dart' show StatusBadge, Tone;
import '../widgets/record_list.dart';

const _minPassword = 10;

/// User administration (admin).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.session});

  final Session session;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  // The loaded list stays on screen while a reload runs (no spinner flash, the scroll position is kept).
  List<Map<String, dynamic>>? _users;
  String? _error;
  bool _loading = false;
  final _search = TextEditingController();
  String _status = '';

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final list = ((await _api.get('/api/users')) as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _users = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _checkPassword(Object? p, {required bool required}) {
    final s = '${p ?? ''}';
    if (s.isEmpty && !required) return;
    if (s.length < _minPassword) throw ApiException(400, 'A senha deve ter ao menos $_minPassword caracteres');
  }

  Future<void> _create() async {
    final r = await submitForm(
      context,
      api: _api,
      title: 'Novo usuário',
      fields: const [
        FieldSpec('username', 'Usuário', required: true),
        FieldSpec('password', 'Senha', required: true, obscure: true, hint: 'Mínimo $_minPassword caracteres'),
        FieldSpec('role', 'Perfil', type: FieldType.choice, required: true, choices: userRoles, defaultValue: 'Reader'),
      ],
      submit: (b) {
        _checkPassword(b['password'], required: true);
        return _api.post('/api/users', {'username': b['username'], 'password': b['password'], 'role': b['role']});
      },
    );
    if (r != null) unawaited(_reload());
  }

  Future<void> _edit(Map<String, dynamic> u) async {
    final r = await submitForm(
      context,
      api: _api,
      title: 'Usuário ${u['username']}',
      fields: const [
        FieldSpec('role', 'Perfil', type: FieldType.choice, required: true, choices: userRoles),
        FieldSpec('active', 'Ativo', type: FieldType.boolean),
        FieldSpec('password', 'Redefinir senha', obscure: true, hint: 'Deixe em branco para manter · mínimo $_minPassword caracteres'),
      ],
      initial: u,
      submit: (b) async {
        _checkPassword(b['password'], required: false);
        final pw = '${b['password'] ?? ''}';
        // Only a change of profile, status or password signs the user out; saving without touching them asks nothing.
        final sensitive = b['role'] != u['role'] || (b['active'] == true) != (u['active'] == true) || pw.isNotEmpty;
        if (sensitive && !await confirm(context, 'Alterar perfil, situação ou senha desconecta ${u['username']} de todos os dispositivos. Continuar?', confirmLabel: 'Salvar e desconectar', cancelLabel: 'Voltar')) {
          // Backing out is not an error: the form stays open and the message is empty.
          throw ApiException(0, '');
        }
        return _api.put('/api/users/${u['id']}', {'role': b['role'], 'active': b['active'] == true, if (pw.isNotEmpty) 'password': pw});
      },
    );
    if (r != null) unawaited(_reload());
  }

  Future<void> _unlock(Map<String, dynamic> u) async {
    await runAction(context, () => _api.post('/api/users/${u['id']}/unlock', <String, dynamic>{}), success: '${u['username']} desbloqueado');
    unawaited(_reload());
  }

  bool _matches(Map<String, dynamic> u) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty && !'${u['username']}'.toLowerCase().contains(q) && !(userRoles['${u['role']}'] ?? '').toLowerCase().contains(q)) return false;
    return switch (_status) {
      'active' => u['active'] == true,
      'inactive' => u['active'] != true,
      'locked' => u['locked'] == true,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final all = _users;
    if (all == null) {
      return _error != null ? LoadError(message: _error!, onRetry: _reload) : const Center(child: CircularProgressIndicator());
    }
    final users = all.where(_matches).toList();
    final filtered = _search.text.trim().isNotEmpty || _status.isNotEmpty;
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  filtered ? '${users.length} de ${all.length} usuários' : '${all.length} ${all.length == 1 ? 'usuário' : 'usuários'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_loading) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              FilledButton.icon(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Novo usuário')),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  TextButton(onPressed: _reload, child: const Text('Tentar novamente')),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('users-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Buscar usuário ou perfil', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                ),
              ),
              ChoiceFilter(
                label: 'Situação',
                value: _status.isEmpty ? null : _status,
                choices: const {'active': 'Ativos', 'inactive': 'Inativos', 'locked': 'Bloqueados'},
                onChanged: (v) => setState(() => _status = v ?? ''),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: filtered
                    ? Column(
                        children: [
                          const Text('Nenhum usuário com esse filtro'),
                          TextButton(
                            onPressed: () => setState(() {
                              _search.clear();
                              _status = '';
                            }),
                            child: const Text('Limpar filtros'),
                          ),
                        ],
                      )
                    : const Text('Nenhum usuário'),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, u) in users.indexed) ...[if (i > 0) const Divider(height: 1), _row(u)],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> u) {
    final locked = u['locked'] == true;
    final name = '${u['username']}';
    return ListTile(
      key: ValueKey('user-${u['id']}'),
      leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name.substring(0, name.length < 2 ? 1 : 2).toUpperCase())),
      title: Text(name),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(userRoles[u['role']] ?? '${u['role']}'),
          StatusBadge(u['active'] == true ? 'Ativo' : 'Inativo', tone: u['active'] == true ? Tone.success : Tone.neutral, icon: Icons.circle),
          if (locked) const StatusBadge('Bloqueado', tone: Tone.danger, icon: Icons.circle),
        ],
      ),
      trailing: locked
          ? TextButton.icon(
              key: ValueKey('unlock-${u['id']}'),
              onPressed: () => _unlock(u),
              icon: const Icon(Icons.lock_open),
              label: const Text('Desbloquear'),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _edit(u),
    );
  }
}
