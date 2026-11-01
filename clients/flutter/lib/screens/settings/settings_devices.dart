import 'package:flutter/material.dart';

import '../../api.dart';
import '../../session.dart';
import 'settings_widgets.dart';

/// One signed-in device (refresh-token session) of the current user.
class DeviceInfo {
  DeviceInfo(Map<String, dynamic> j)
    : id = (j['id'] as num).toInt(),
      device = j['device'] as String?,
      userAgent = j['userAgent'] as String?,
      ip = j['ip'] as String?,
      createdAt = DateTime.tryParse('${j['createdAt'] ?? ''}'),
      expiresAt = DateTime.tryParse('${j['expiresAt'] ?? ''}'),
      current = j['current'] == true;

  final int id;
  final String? device, userAgent, ip;
  final DateTime? createdAt, expiresAt;
  final bool current;

  String get title => (device?.trim().isNotEmpty ?? false) ? device!.trim() : 'Dispositivo sem nome';
}

/// The sessions signed in with this user; the current device is marked and cannot be disconnected from here.
class DevicesView extends StatefulWidget {
  const DevicesView({super.key, required this.session});

  final Session session;

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  int _version = 0;
  bool _busy = false;
  String? _error;

  Future<List<DeviceInfo>> _load() async {
    final raw = await widget.session.api.post('/api/auth/sessions', {'refreshToken': widget.session.api.refreshToken}) as List;
    return [for (final j in raw) DeviceInfo(j as Map<String, dynamic>)];
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      setState(() => _version++);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desconectar os outros dispositivos?'),
        content: const Text('Todos os outros aparelhos e navegadores precisam entrar de novo. Este continua conectado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('devices-confirm-others'), onPressed: () => Navigator.pop(c, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (ok == true) await _run(widget.session.revokeOtherSessions, 'Os outros dispositivos foram desconectados');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LoadView<List<DeviceInfo>>(
      key: ValueKey(_version),
      load: _load,
      builder: (context, devices, reload) {
        final others = devices.where((d) => !d.current).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Cada linha é uma sessão aberta com o seu usuário. Desconectar uma sessão a encerra no próximo uso; o acesso já aberto naquele aparelho pode durar até uma hora.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (devices.isEmpty) const Text('Nenhuma sessão ativa encontrada.'),
            for (final d in devices)
              Card(
                key: ValueKey('device-${d.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(d.current ? Icons.computer : Icons.devices_other_outlined),
                  title: Row(
                    children: [
                      Flexible(child: Text(d.title)),
                      if (d.current)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(label: const Text('Este dispositivo'), visualDensity: VisualDensity.compact, backgroundColor: theme.colorScheme.primaryContainer),
                        ),
                    ],
                  ),
                  subtitle: Text([
                    if (d.ip != null) 'IP ${d.ip}',
                    if (d.createdAt != null) 'Conectado em ${formatMoment(d.createdAt!)}',
                    if (d.expiresAt != null) 'Válido até ${formatMoment(d.expiresAt!)}',
                  ].join('  ·  ')),
                  trailing: d.current
                      ? null
                      : TextButton(
                          key: ValueKey('device-disconnect-${d.id}'),
                          onPressed: _busy ? null : () => _run(() async => widget.session.api.delete('/api/auth/sessions/${d.id}'), 'Dispositivo desconectado'),
                          child: const Text('Desconectar'),
                        ),
                ),
              ),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('devices-revoke-others'),
                  onPressed: _busy || others == 0 ? null : _revokeOthers,
                  icon: const Icon(Icons.logout),
                  label: Text(others == 0 ? 'Nenhum outro dispositivo' : 'Desconectar os outros ($others)'),
                ),
                OutlinedButton.icon(onPressed: _busy ? null : reload, icon: const Icon(Icons.refresh), label: const Text('Atualizar')),
              ],
            ),
          ],
        );
      },
    );
  }
}
