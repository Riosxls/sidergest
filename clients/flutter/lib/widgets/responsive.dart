import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// True on phones and tablets, where touch targets must be larger and hover does nothing.
bool get isTouchPlatform => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Width for a dialog that wants [ideal] pixels: never wider than the window minus a margin, so it does not overflow phones.
double dialogWidth(BuildContext context, [double ideal = 560]) {
  final w = MediaQuery.sizeOf(context).width - 48;
  return ideal < w ? ideal : w;
}

/// Wraps dialog content so it keeps at most [ideal] pixels but shrinks on narrow windows.
class DialogBody extends StatelessWidget {
  const DialogBody({super.key, required this.child, this.ideal = 560});

  final Widget child;
  final double ideal;

  @override
  Widget build(BuildContext context) => SizedBox(width: dialogWidth(context, ideal), child: child);
}

/// Scales a fixed [height] with the text scaler so rows and tiles do not clip at large text sizes.
double scaledHeight(BuildContext context, double height) => MediaQuery.textScalerOf(context).scale(height);

/// Pads [child] up to [kMinTouchTarget] logical pixels in both directions so small icons stay easy to hit.
class TouchTarget extends StatelessWidget {
  const TouchTarget({super.key, required this.child, this.size = 44});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    child: Center(child: child),
  );
}
