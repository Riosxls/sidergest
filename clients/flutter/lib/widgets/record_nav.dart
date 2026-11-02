import 'package:flutter/material.dart';

/// Tracks the pages of one [Navigator]: how many are open and which records they show.
///
/// Add one to `navigatorObservers` (root) and to the Shell's inner navigator; [pushRecord] reads it from the navigator it pushes to.
class RecordTrail extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// Number of page routes in the stack, the first one included. Updated after the frame so listeners may call `setState`.
  final ValueNotifier<int> pages = ValueNotifier(0);

  bool has(String name) => _stack.any((r) => r.settings.name == name);

  void _sync() => WidgetsBinding.instance.addPostFrameCallback((_) => pages.value = _stack.whereType<PageRoute<dynamic>>().length);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _sync();
  }
}

/// Opens a record page (`kind:id`). A link back to a record already open in this navigator returns to it
/// instead of stacking the same page again, so quote → order → quote → order chains stay as long as the user's path.
Future<T?> pushRecord<T>(BuildContext context, String kind, int id, WidgetBuilder builder) {
  final nav = Navigator.of(context);
  final name = 'record:$kind:$id';
  final trail = nav.widget.observers.whereType<RecordTrail>().firstOrNull;
  if (trail != null && trail.has(name)) {
    nav.popUntil((r) => r.settings.name == name);
    return Future.value();
  }
  return nav.push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name),
      builder: builder,
    ),
  );
}
