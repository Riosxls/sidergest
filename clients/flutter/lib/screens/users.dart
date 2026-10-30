import 'package:flutter/material.dart';

import '../api.dart';
import '../entities.dart';
import '../labels.dart';
import '../session.dart';
import '../widgets/actions.dart';
import '../widgets/entity_form.dart';
import '../widgets/record_list.dart';

const _minPassword = 10;

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.session});

  final Session session;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _future = _fetch();

  ApiClient get _api => widget.session.api;

  Future<List<Map<String, dynamic>>> _fetch() async => ((await _api.get('/api/users')) as List).cast<Map<String, dynamic>>();

  void _reload() => setState(() {
    _future = _fetch();
  });

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
    if (r != null) _reload();
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
        if (!await confirm(context, 'Alterar perfil, situação ou senha desconecta ${u['username']} de todos os dispositivos. Continuar?')) {
          throw ApiException(0, 'Alteração não confirmada');
        }
        final pw = '${b['password'] ?? ''}';
        return _api.put('/api/users/${u['id']}', {'role': b['role'], 'active': b['active'] == true, if (pw.isNotEmpty) 'password': pw});
      },
    );
    if (r != null) _reload();
  }

  Future<void> _unlock(Map<String, dynamic> u) async {
    await runAction(context, () => _api.post('/api/users/${u['id']}/unlock', <String, dynamic>{}), success: '${u['username']} desbloqueado');
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Novo usuário')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text(friendlyError(snap.error!)));
        final users = snap.data;
        if (users == null) return const Center(child: CircularProgressIndicator());
        if (users.isEmpty) return const Center(child: Text('Nenhum usuário'));
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: users.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final u = users[i];
            final locked = u['locked'] == true;
            return ListTile(
              key: ValueKey('user-${u['id']}'),
              leading: const Icon(Icons.person_outline),
              title: Text('${u['username']}'),
              subtitle: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(userRoles[u['role']] ?? '${u['role']}'),
                  StatusChip(u['active'] == true ? 'Ativo' : 'Inativo', ok: u['active'] == true),
                  if (locked) const StatusChip('Bloqueado', alert: true),
                ],
              ),
              trailing: locked
                  ? TextButton.icon(key: ValueKey('unlock-${u['id']}'), onPressed: () => _unlock(u), icon: const Icon(Icons.lock_open), label: const Text('Desbloquear'))
                  : null,
              onTap: () => _edit(u),
            );
          },
        );
      },
    ),
  );
}
