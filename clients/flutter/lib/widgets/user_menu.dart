import 'package:flutter/material.dart';

import '../session.dart';

class UserMenu extends StatelessWidget {
  const UserMenu({super.key, required this.session});

  final Session session;

  String get _initials {
    final name = (session.username ?? '?').trim();
    return name.isEmpty ? '?' : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _profile(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Perfil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Usuário: ${session.username ?? ''}'),
          Text('Perfil de acesso: ${session.role ?? ''}'),
          Text('Servidor: ${session.baseUrl}'),
          if (session.expiresAt != null) Text('Sessão válida até ${_fmt(session.expiresAt!.toLocal())}'),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ),
  );

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  PopupMenuItem<String> _theme(String value, ThemeMode mode, String label, IconData icon) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (session.themeMode == mode) const Icon(Icons.check, size: 18),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Conta',
      offset: const Offset(0, 44),
      onSelected: (v) {
        switch (v) {
          case 'profile':
            _profile(context);
          case 'light':
            session.setThemeMode(ThemeMode.light);
          case 'dark':
            session.setThemeMode(ThemeMode.dark);
          case 'system':
            session.setThemeMode(ThemeMode.system);
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
              Text(session.username ?? '', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
              Text(session.role ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: Row(children: [Icon(Icons.person_outline, size: 20), SizedBox(width: 12), Text('Perfil')]),
        ),
        const PopupMenuDivider(),
        _theme('system', ThemeMode.system, 'Tema do sistema', Icons.brightness_auto_outlined),
        _theme('light', ThemeMode.light, 'Tema claro', Icons.light_mode_outlined),
        _theme('dark', ThemeMode.dark, 'Tema escuro', Icons.dark_mode_outlined),
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
