import 'package:flutter/material.dart';

class AlertInfo {
  const AlertInfo(this.icon, this.label, this.count, this.navId, [this.filter]);

  final IconData icon;
  final String label;
  final int count;
  final String navId;
  final String? filter;
}

class AlertCenter extends ValueNotifier<List<AlertInfo>> {
  AlertCenter() : super(const []);

  int get total => value.fold(0, (n, a) => n + a.count);
}

class AlertBell extends StatelessWidget {
  const AlertBell({super.key, required this.center, required this.onNavigate});

  final AlertCenter center;
  final void Function(String id, [String? filter]) onNavigate;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<AlertInfo>>(
    valueListenable: center,
    builder: (context, alerts, _) {
      final total = center.total;
      return PopupMenuButton<AlertInfo>(
        tooltip: total == 0 ? 'Notificações' : 'Notificações ($total)',
        offset: const Offset(0, 44),
        onSelected: (a) => onNavigate(a.navId, a.filter),
        itemBuilder: (_) => alerts.isEmpty
            ? [const PopupMenuItem<AlertInfo>(enabled: false, child: Text('Nenhum alerta'))]
            : [
                for (final a in alerts)
                  PopupMenuItem<AlertInfo>(
                    value: a,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 20, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(child: Text(a.label)),
                        const SizedBox(width: 16),
                        Text('${a.count}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: total > 0,
            label: Text(total > 99 ? '99+' : '$total'),
            child: Icon(total > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
          ),
        ),
      );
    },
  );
}
