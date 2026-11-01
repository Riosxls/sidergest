import 'package:flutter/widgets.dart';

/// Multiplies the platform text scale (OS or browser setting) by the app's own [factor] (Normal = 1), kept within 0.8 to 2.0.
class AppTextScale extends StatelessWidget {
  const AppTextScale({super.key, required this.factor, required this.child});

  final double factor;
  final Widget child;

  static const min = 0.8;
  static const max = 2.0;

  @override
  Widget build(BuildContext context) {
    final os = MediaQuery.textScalerOf(context).scale(1);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear((os * factor).clamp(min, max))),
      child: child,
    );
  }
}
