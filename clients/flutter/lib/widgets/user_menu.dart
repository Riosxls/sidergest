import 'package:flutter/material.dart';

import '../labels.dart';
import '../screens/settings/settings_dialog.dart';
import '../screens/settings/settings_widgets.dart' show formatMoment;
import '../session.dart';
import '../theme_tokens.dart';

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

  /// Avatar, name, e-mail, role and the time of the access before this one; fixed width so the menu does not size itself to a long address.
  Widget _header(ThemeData theme) {
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final previous = session.previousLoginAt;
    final email = session.email?.trim() ?? '';
    return SizedBox(
      width: 248,
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: Text(_initials, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurface)),
                if (email.isNotEmpty) Text(email, key: const ValueKey('menu-email'), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                Text(userRoles[session.role] ?? session.role ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                if (previous != null) Text('Último acesso: ${formatMoment(previous)}', key: const ValueKey('menu-last-login'), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Theme and text size without opening the settings; follows the session, since the popup is built once and stays open while the user taps.
  Widget _appearance(ThemeData theme) => SizedBox(
    width: 248,
    child: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        const choices = Session.textScaleChoices;
        final i = choices.indexOf(Session.snapTextScale(session.textScale));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Aparência', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<ThemeMode>(
              key: const ValueKey('menu-theme'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8))),
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18), tooltip: 'Claro'),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18), tooltip: 'Escuro'),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined, size: 18), tooltip: 'Automático'),
              ],
              selected: {session.themeMode},
              onSelectionChanged: (s) => session.setThemeMode(s.first),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: Text('Texto ${(choices[i] * 100).round()}%', style: theme.textTheme.bodyMedium)),
                IconButton(
                  key: const ValueKey('menu-text-smaller'),
                  tooltip: 'Diminuir texto',
                  visualDensity: VisualDensity.compact,
                  onPressed: i <= 0 ? null : () => session.setTextScale(choices[i - 1]),
                  icon: const Text('A-', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  key: const ValueKey('menu-text-larger'),
                  tooltip: 'Aumentar texto',
                  visualDensity: VisualDensity.compact,
                  onPressed: i >= choices.length - 1 ? null : () => session.setTextScale(choices[i + 1]),
                  icon: const Text('A+', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        );
      },
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
            showUserSettings(context, session, section: 'account');
          case 'appearance':
            showUserSettings(context, session, section: 'appearance');
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
        PopupMenuItem<String>(key: const ValueKey('menu-header'), enabled: false, height: 72, child: _header(theme)),
        const PopupMenuDivider(),
        // Enabled on purpose: a disabled item dims its icons and text, so the controls looked dead. A tap beside a control just closes the menu.
        PopupMenuItem<String>(key: const ValueKey('menu-appearance'), child: _appearance(theme)),
        const PopupMenuItem<String>(
          key: ValueKey('menu-appearance-more'),
          value: 'appearance',
          height: 36,
          child: Row(children: [Icon(Icons.palette_outlined, size: 20), SizedBox(width: 12), Flexible(child: Text('Mais em Aparência', overflow: TextOverflow.ellipsis))]),
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
