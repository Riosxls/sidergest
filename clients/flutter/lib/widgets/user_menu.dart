import 'package:flutter/material.dart';

import '../screens/settings/settings_dialog.dart';
import '../session.dart';

/// Avatar menu: opens settings and signs out.
class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.session});

  final Session session;

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
            session.logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.shownName, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
              Text(session.role ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [Icon(Icons.logout, size: 20), SizedBox(width: 12), Text('Sair')]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(_initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
