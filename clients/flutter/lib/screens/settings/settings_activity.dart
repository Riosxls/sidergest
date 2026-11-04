import 'package:flutter/material.dart';

import '../../api.dart';
import '../../labels.dart';
import '../../session.dart';
import '../../theme_tokens.dart';
import '../../widgets/load_error.dart';
import '../audit.dart' show auditEntityName, humanizeField;
import 'settings_widgets.dart';

/// One sign-in of the current user, as listed by `GET /api/auth/my-activity`.
class LoginEntry {
  LoginEntry(Map<String, dynamic> j)
    : at = DateTime.tryParse('${j['at'] ?? ''}'),
      device = j['device'] as String?,
      userAgent = j['userAgent'] as String?,
      ip = j['ip'] as String?,
      current = j['current'] == true;

  final DateTime? at;
  final String? device, userAgent, ip;
  final bool current;

  /// The device name the app sent, else a short reading of the browser/OS text, else a neutral label.
  String get title {
    if (device?.trim().isNotEmpty ?? false) return device!.trim();
    return summarizeUserAgent(userAgent) ?? 'Dispositivo desconhecido';
  }
}

/// One audited change made by the current user.
class ChangeEntry {
  ChangeEntry(Map<String, dynamic> j)
    : at = DateTime.tryParse('${j['at'] ?? ''}'),
      entity = '${j['entity'] ?? ''}',
      entityId = j['entityId'] == null ? null : '${j['entityId']}',
      action = '${j['action'] ?? ''}',
      summary = j['summary'] as String?;

  final DateTime? at;
  final String entity, action;
  final String? entityId, summary;
}

/// "Chrome no Windows" from a user-agent text; null when nothing is recognised.
String? summarizeUserAgent(String? ua) {
  if (ua == null || ua.trim().isEmpty) return null;
  final browser = ua.contains('Edg/')
      ? 'Edge'
      : ua.contains('Firefox/')
      ? 'Firefox'
      : ua.contains('Chrome/')
      ? 'Chrome'
      : ua.contains('Safari/')
      ? 'Safari'
      : null;
  final os = ua.contains('Android')
      ? 'Android'
      : (ua.contains('iPhone') || ua.contains('iPad'))
      ? 'iOS'
      : ua.contains('Windows')
      ? 'Windows'
      : ua.contains('Mac OS')
      ? 'macOS'
      : ua.contains('Linux')
      ? 'Linux'
      : null;
  if (browser != null && os != null) return '$browser no $os';
  return browser ?? os ?? (ua.length > 40 ? '${ua.substring(0, 40)}…' : ua);
}

typedef _Activity = ({List<LoginEntry> logins, List<ChangeEntry> changes});

/// "Minha atividade": the user's recent sign-ins and the changes they made, so a use of the account they do not recognise stands out.
class ActivityView extends StatefulWidget {
  const ActivityView({super.key, required this.session});

  final Session session;

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  late Future<_Activity> _future = _load();
  bool _showChanges = false;

  Future<_Activity> _load() async {
    final r = await widget.session.api.myActivity();
    final m = r is Map ? r : const {};
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) make) => [
      if (raw is List)
        for (final j in raw)
          if (j is Map) make(Map<String, dynamic>.from(j)),
    ];
    return (logins: list(m['logins'], LoginEntry.new), changes: list(m['changes'], ChangeEntry.new));
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seus acessos e as alterações feitas com o seu usuário. Se algo não for seu, troque a senha e desconecte os outros dispositivos em Conta e acesso.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<bool>(
          key: const ValueKey('activity-tabs'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.login), label: Text('Últimos acessos')),
            ButtonSegment(value: true, icon: Icon(Icons.edit_note), label: Text('Minhas alterações')),
          ],
          selected: {_showChanges},
          onSelectionChanged: (s) => setState(() => _showChanges = s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<_Activity>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return LoadError(message: friendlyError(snap.error!), onRetry: _retry);
            final data = snap.data;
            if (data == null) return const _ActivitySkeleton();
            return _showChanges ? _changes(context, data.changes) : _logins(context, data.logins);
          },
        ),
      ],
    );
  }

  Widget _empty(String text, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );

  Widget _logins(BuildContext context, List<LoginEntry> logins) {
    if (logins.isEmpty) return _empty('Nenhum acesso registrado ainda.', key: const ValueKey('activity-logins-empty'));
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < logins.length; i++)
          Card(
            key: ValueKey('activity-login-$i'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Icon(logins[i].current ? Icons.computer : Icons.devices_other_outlined),
              title: Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(logins[i].title),
                  if (logins[i].current)
                    Chip(label: const Text('Este dispositivo'), visualDensity: VisualDensity.compact, backgroundColor: theme.colorScheme.primaryContainer),
                ],
              ),
              subtitle: Text([
                if (logins[i].at != null) formatMoment(logins[i].at!),
                if (logins[i].ip != null && logins[i].ip!.isNotEmpty) 'IP ${logins[i].ip}',
                if ((logins[i].device?.trim().isNotEmpty ?? false) && summarizeUserAgent(logins[i].userAgent) != null) summarizeUserAgent(logins[i].userAgent)!,
              ].join('  ·  ')),
            ),
          ),
      ],
    );
  }

  Widget _changes(BuildContext context, List<ChangeEntry> changes) {
    if (changes.isEmpty) return _empty('Você ainda não fez alterações registradas.', key: const ValueKey('activity-changes-empty'));
    return Column(
      children: [
        for (var i = 0; i < changes.length; i++)
          Card(
            key: ValueKey('activity-change-$i'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${auditActions[changes[i].action] ?? humanizeField(changes[i].action)} · ${auditEntityName(changes[i].entity)}${changes[i].entityId == null ? '' : ' #${changes[i].entityId}'}',
              ),
              subtitle: Text([
                if (changes[i].at != null) formatMoment(changes[i].at!),
                if (changes[i].summary?.trim().isNotEmpty ?? false) changes[i].summary!.trim(),
              ].join('  ·  ')),
            ),
          ),
      ],
    );
  }
}

/// Quiet blocks in the shape of the list while it loads.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: 'Carregando',
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('activity-skeleton'),
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: 64,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.card)),
            ),
        ],
      ),
    );
  }
}
