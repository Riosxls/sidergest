import 'package:flutter/material.dart';

import '../../session.dart';
import '../data_reset.dart';
import '../legacy_cleanup.dart';
import 'settings_backup.dart';
import 'settings_data_source.dart';
import 'settings_widgets.dart';

/// Backups older than this are flagged: the nightly task should have run since.
const staleBackupAfter = Duration(hours: 36);

/// Shows the age of the latest database backup (admin).
class BackupStatus {
  BackupStatus(Map<String, dynamic> j)
    : configured = j['configured'] == true,
      count = (j['count'] as num?)?.toInt() ?? 0,
      lastBackupAt = DateTime.tryParse('${j['lastBackupAt'] ?? ''}'),
      lastBackupFile = j['lastBackupFile'] as String?,
      lastBackupSizeBytes = (j['lastBackupSizeBytes'] as num?)?.toInt();

  final bool configured;
  final int count;
  final DateTime? lastBackupAt;
  final String? lastBackupFile;
  final int? lastBackupSizeBytes;

  bool get stale => lastBackupAt == null || DateTime.now().difference(lastBackupAt!) > staleBackupAfter;
}

/// Last restore drill, as the anonymous `/health/ready` reports it (null when none ran or the call fails).
class DrillInfo {
  DrillInfo({required this.ok, this.at});

  final bool ok;
  final DateTime? at;

  static DrillInfo? from(Object? ready) {
    final backup = ready is Map ? ready['backup'] : null;
    final drill = backup is Map ? backup['drill'] : null;
    if (drill is! Map) return null;
    final raw = drill['at'] ?? drill['ranAt'] ?? drill['finishedAt'];
    return DrillInfo(ok: drill['ok'] == true, at: raw == null ? null : DateTime.tryParse('$raw')?.toLocal());
  }
}

/// Backup section of the settings dialog (admin only): state, schedule, run now and restore.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Estado',
          children: [
            LoadView<BackupStatus?>(
              load: () async {
                try {
                  return BackupStatus(await session.api.get('/api/admin/backup-status') as Map<String, dynamic>);
                } catch (e) {
                  debugPrint('settings_admin: lookup failed, using fallback: $e');
                  return null;
                }
              },
              builder: (context, b, reload) {
                final (IconData icon, Color color, String headline, String detail) = b == null
                    ? (Icons.help_outline, theme.colorScheme.onSurfaceVariant, 'Não foi possível consultar', 'O servidor não respondeu.')
                    : !b.configured
                    ? (Icons.info_outline, theme.colorScheme.onSurfaceVariant, 'Pasta de backups não ligada ao servidor', 'O backup roda pelo script do computador; o servidor só mostra o estado se enxergar a pasta "backups".')
                    : b.lastBackupAt == null
                    ? (Icons.warning_amber_rounded, theme.colorScheme.error, 'Nenhum backup encontrado', 'Rode scripts\\backup.ps1 ou confira a tarefa noturna.')
                    : b.stale
                    ? (Icons.warning_amber_rounded, theme.colorScheme.error, 'Último backup está velho', 'Passou de ${staleBackupAfter.inHours} horas. Confira a tarefa noturna em docs/OPERATIONS.md.')
                    : (Icons.check_circle_outline, theme.colorScheme.primary, 'Backup em dia', 'O último tem menos de ${staleBackupAfter.inHours} horas.');
                return Card(
                  key: const ValueKey('settings-backup'),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: color),
                            const SizedBox(width: 10),
                            Expanded(child: Text(headline, style: theme.textTheme.titleSmall)),
                            IconButton(tooltip: 'Consultar de novo', onPressed: reload, icon: const Icon(Icons.refresh)),
                          ],
                        ),
                        Text(detail),
                        if (b != null && b.lastBackupAt != null) ...[
                          const SizedBox(height: 8),
                          Text('Último: ${formatMoment(b.lastBackupAt!)}${b.lastBackupSizeBytes == null ? '' : '  ·  ${(b.lastBackupSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'}'),
                          if (b.lastBackupFile != null) Text(b.lastBackupFile!, style: theme.textTheme.bodySmall),
                          Text('${b.count} arquivos guardados', style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            LoadView<DrillInfo?>(
              load: () async {
                try {
                  return DrillInfo.from(await session.api.get('/health/ready'));
                } catch (e) {
                  debugPrint('settings_admin: drill lookup failed: $e');
                  return null;
                }
              },
              builder: (context, d, reload) => d == null
                  ? Text('Teste de restauração: ainda não rodou.', key: const ValueKey('settings-drill'), style: theme.textTheme.bodySmall)
                  : Row(
                      key: const ValueKey('settings-drill'),
                      children: [
                        Icon(d.ok ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18, color: d.ok ? theme.colorScheme.primary : theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${d.ok ? 'Último teste de restauração passou' : 'Último teste de restauração falhou'}${d.at == null ? '' : ' em ${formatMoment(d.at!)}'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        BackupSettingsView(session: session),
      ],
    );
  }
}

/// Dados do sistema section of the settings dialog (admin only): data source, legacy cleanup and reset.
class AdminSection extends StatelessWidget {
  const AdminSection({super.key, required this.session, required this.open});

  final Session session;
  final OpenSubView open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: 'Origem dos dados',
          children: [
            SettingsLink(
              key: const ValueKey('settings-open-data-source'),
              icon: Icons.fact_check_outlined,
              title: 'Fonte dos dados',
              subtitle: 'Quantos registros são manuais, importados ou de teste, e como marcá-los',
              onTap: () => open('Fonte dos dados', (_) => DataSourceView(session: session)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Sistema antigo',
          note: 'Ordens de fabricação do sistema antigo: preenche o processo das que estão vazias e cancela as vencidas que nunca andaram.',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('open-legacy-cleanup'),
                onPressed: () => showLegacyCleanupDialog(context, session),
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Limpeza do legado…'),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Zona de perigo: recomeçar do zero',
          note:
              'Apaga orçamentos, pedidos, entregas, ordens de fabricação e outros registros do dia a dia. Produtos, materiais, clientes, fornecedores, ferramentas e preços ficam como estão. Faça um backup antes.',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('open-data-reset'),
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () => showDataResetDialog(context, session),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Limpar dados de movimento…'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
