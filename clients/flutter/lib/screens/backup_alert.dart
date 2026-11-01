import 'package:flutter/material.dart';

import '../session.dart';
import 'settings/settings_backup.dart';
import 'settings/settings_dialog.dart';

/// A backup problem shown on the Painel (admin only).
class BackupAlert {
  const BackupAlert(this.title, this.detail);

  final String title;
  final String detail;
}

const _cancelledMessage = 'Backup cancelado.';
const _agentSilentAfter = Duration(minutes: 15);
const _staleAfter = Duration(hours: 36);

/// First matching backup problem, or null when all is well: last run failed, backup program stopped, backup overdue.
BackupAlert? backupAlertFor(BackupSettings s, DateTime now) {
  final message = s.lastRunMessage?.trim();
  if (s.lastRunOk == false && message != _cancelledMessage) {
    final short = message == null || message.isEmpty ? 'O último backup não terminou.' : (message.length > 160 ? '${message.substring(0, 157)}...' : message);
    return BackupAlert('Último backup falhou', short);
  }
  final seen = s.agentSeenAt;
  final requested = s.runRequestedAt;
  final recentRequest = requested != null && now.difference(requested) < const Duration(hours: 24);
  if ((seen == null || now.difference(seen) > _agentSilentAfter) && (s.enabled || recentRequest)) {
    return const BackupAlert('Programa de backup parado', 'O programa que executa os backups no computador não está ativo.');
  }
  if (s.enabled) {
    final last = s.lastRunAt;
    if (last == null) return const BackupAlert('Backup atrasado', 'Nenhum backup feito ainda.');
    final age = now.difference(last);
    if (age > _staleAfter) return BackupAlert('Backup atrasado', 'Último backup há ${age.inHours} horas.');
  }
  return null;
}

/// Reads the backup settings for the Painel; null when the user is not admin or the request fails.
Future<BackupAlert?> fetchBackupAlert(Session session, {DateTime? now}) async {
  if (!session.isAdmin) return null;
  try {
    final j = await session.api.get('/api/admin/backup-settings') as Map<String, dynamic>;
    return backupAlertFor(BackupSettings.fromJson(j), now ?? DateTime.now());
  } catch (e) {
    debugPrint('dashboard: backup alert failed: $e');
    return null;
  }
}

/// Error-colored card for a [BackupAlert]; opens the Administração section of the settings.
class BackupAlertCard extends StatelessWidget {
  const BackupAlertCard({super.key, required this.alert, required this.session});

  final BackupAlert alert;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      key: const ValueKey('alert-backup'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
      ),
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => showUserSettings(context, session, section: 'admin'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.backup_outlined, size: 32, color: cs.error),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title, style: theme.textTheme.titleMedium?.copyWith(color: cs.error)),
                    Text(alert.detail, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
