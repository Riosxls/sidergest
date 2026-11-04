import 'package:flutter/material.dart';

import '../../api.dart';
import '../../session.dart';
import '../../theme_tokens.dart';
import '../dashboard.dart' show alertModules, legacyOverdueDays;
import 'settings_widgets.dart';

/// Settings section: which alerts reach the Painel and the bell. Each module can be silenced (its alerts leave the bell count and the
/// Atenção block, which still says how many were silenced); alerts about the system's own safety are always on.
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key, required this.session});

  final Session session;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The copy kept in the session may predate a change made on another device.
    widget.session.loadNotificationPrefs();
  }

  /// Saves right away; the switches already show the new value and [Session.saveNotificationPrefs] puts the old one back on failure.
  Future<void> _save({Set<String>? muted, bool? hideLegacy}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.session.saveNotificationPrefs(muted: muted, hideLegacy: hideLegacy);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            title: 'Alertas por módulo',
            note: 'Silenciar um módulo tira os alertas dele do sino e do bloco Atenção do Painel. O Painel continua dizendo quantos alertas foram silenciados.',
            children: [
              for (final m in alertModules)
                SwitchListTile(
                  key: ValueKey('notif-${m.key}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.title),
                  subtitle: Text(s.mutedAlerts.contains(m.key) ? 'Silenciado' : 'Alertas ativos'),
                  // On means "I want these alerts".
                  value: !s.mutedAlerts.contains(m.key),
                  onChanged: _busy
                      ? null
                      : (on) => _save(muted: {...s.mutedAlerts.where((k) => k != m.key), if (!on) m.key}),
                ),
            ],
          ),
          SettingsGroup(
            title: 'Pendências antigas',
            children: [
              SwitchListTile(
                key: const ValueKey('notif-hide-legacy'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Ocultar pendências antigas (legado)'),
                subtitle: const Text('Esconde do Painel os atrasos de mais de $legacyOverdueDays dias, vindos do sistema antigo.'),
                value: s.hideLegacyAlerts,
                onChanged: _busy ? null : (v) => _save(hideLegacy: v),
              ),
            ],
          ),
          const SettingsGroup(
            title: 'Sempre ativos',
            note: 'Avisos sobre a segurança dos dados não podem ser silenciados.',
            children: [
              SwitchListTile(
                key: ValueKey('notif-always-backup'),
                contentPadding: EdgeInsets.zero,
                title: Text('Falha ou atraso da cópia de segurança'),
                subtitle: Text('Sempre ativo · mostrado aos administradores no Painel'),
                value: true,
                onChanged: null,
              ),
              SwitchListTile(
                key: ValueKey('notif-always-security'),
                contentPadding: EdgeInsets.zero,
                title: Text('Avisos de sessão e segurança da conta'),
                subtitle: Text('Sempre ativo · bloqueio por inatividade, sessão encerrada'),
                value: true,
                onChanged: null,
              ),
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Salvando…', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
