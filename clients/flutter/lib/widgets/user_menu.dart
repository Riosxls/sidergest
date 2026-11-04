import 'package:flutter/material.dart';

import '../labels.dart';
import '../screens/settings/settings_dialog.dart';
import '../session.dart';

/// Avatar menu: opens settings, the administration screens and signs out.
class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.session, this.adminScreens = const [], this.onOpenScreen});

  final Session session;

  /// Administration screens the user may open; kept here instead of the sidebar so they are not repeated on every screen.
  final List<({String id, IconData icon, String title})> adminScreens;
  final void Function(String id)? onOpenScreen;

  String get _initials {
    final name = session.shownName.trim();
    return name.isEmpty ? '?' : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Conta',
      offset: const Offset(0, 44),
      onSelected: (v) {
        switch (v) {
          case 'profile':
            showUserSettings(context, session, section: 'account');
          case 'settings':
            showUserSettings(context, session);
          case 'logout':
            session.signedOutManually = true;
            session.logout();
          default:
            if (v.startsWith('screen:')) onOpenScreen?.call(v.substring('screen:'.length));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.shownName, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
              Text(userRoles[session.role] ?? session.role ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: Row(children: [Icon(Icons.person_outline, size: 20), SizedBox(width: 12), Text('Perfil')]),
        ),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Row(children: [Icon(Icons.settings_outlined, size: 20), SizedBox(width: 12), Text('Configurações')]),
        ),
        if (adminScreens.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(session.isAdmin ? 'Administração' : 'Sistema', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          for (final s in adminScreens)
            PopupMenuItem<String>(
              key: ValueKey('admin-${s.id}'),
              value: 'screen:${s.id}',
              child: Row(children: [Icon(s.icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(s.title, overflow: TextOverflow.ellipsis))]),
            ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [Icon(Icons.logout, size: 20), SizedBox(width: 12), Text('Sair')]),
        ),
      ],
      child: Semantics(label: 'Conta de ${session.shownName}', button: true, excludeSemantics: true, child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48), child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(_initials, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      )))),
    );
  }
}
