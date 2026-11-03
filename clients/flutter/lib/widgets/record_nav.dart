import 'package:flutter/material.dart';

import 'discard_guard.dart';

/// The record page on top of a navigator: its kind, its id and, when it was opened from a list, the ids of that list in order.
class RecordTop {
  const RecordTop(this.kind, this.id, this.siblings);

  final String kind;
  final int id;
  final List<int>? siblings;

  /// Position of this record among [siblings], or -1 when it has none.
  int get index => siblings?.indexOf(id) ?? -1;

  @override
  bool operator ==(Object other) => other is RecordTop && other.kind == kind && other.id == id && other.siblings == siblings;

  @override
  int get hashCode => Object.hash(kind, id, siblings);

  /// `/r/kind/id`, the form kept in the address bar and in [RecordTrail] restores.
  String get path => '/r/$kind/$id';
}

/// Route name of a record page.
String recordRouteName(String kind, int id) => 'record:$kind:$id';

/// Ids of the list a record was opened from, handed from the list row to [pushRecord] so the page can step to its neighbours.
class RecordSiblings {
  static List<int>? _ids;
  static DateTime? _at;

  /// A list calls this right before it opens one of its rows.
  static void offer(Iterable<Object?> ids) {
    _ids = [
      for (final i in ids)
        if (i is int) i,
    ];
    _at = DateTime.now();
  }

  /// The offered ids when [id] is one of them and the offer is fresh; an offer is used once.
  static List<int>? take(int id) {
    final ids = _ids, at = _at;
    _ids = null;
    _at = null;
    if (ids == null || at == null || DateTime.now().difference(at) > const Duration(seconds: 3) || !ids.contains(id)) return null;
    return ids;
  }
}

/// Tracks the pages of one [Navigator]: how many are open and which records they show.
///
/// Add one to `navigatorObservers` (root) and to the Shell's inner navigator; [pushRecord] reads it from the navigator it pushes to.
class RecordTrail extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];
  RecordTop? _lastTop;

  /// Number of page routes in the stack, the first one included. Updated after the frame so listeners may call `setState`.
  final ValueNotifier<int> pages = ValueNotifier(0);

  /// Route names of the open records, oldest first.
  final ValueNotifier<List<String>> records = ValueNotifier(const []);

  /// The record page on top of whichever navigator changed last, or null when none is open.
  static final ValueNotifier<RecordTop?> top = ValueNotifier(null);

  /// Counts every closed page; lists reload on it so they never show what a page they opened has just changed.
  static final ValueNotifier<int> closed = ValueNotifier(0);

  bool has(String name) => _stack.any((r) => r.settings.name == name);

  void _sync({bool closedPage = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    pages.value = _stack.whereType<PageRoute<dynamic>>().length;
    final names = [
      for (final r in _stack)
        if (r.settings.name?.startsWith('record:') ?? false) r.settings.name!,
    ];
    if (names.length != records.value.length || !_same(names, records.value)) records.value = names;
    RecordTop? t;
    for (final r in _stack.reversed) {
      final parts = r.settings.name?.split(':');
      if (parts != null && parts.length == 3 && parts[0] == 'record') {
        final a = r.settings.arguments;
        t = RecordTop(parts[1], int.tryParse(parts[2]) ?? 0, a is List<int> ? a : null);
        break;
      }
    }
    // The root navigator has no records while the Shell's inner one has: do not let it erase the inner one's value.
    if (t != _lastTop && (t != null || _lastTop != null)) top.value = t;
    _lastTop = t;
    if (closedPage) closed.value++;
  });

  static bool _same(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync(closedPage: route is PageRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync(closedPage: route is PageRoute);
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
/// Pages with unsaved edits are not closed without asking.
Future<T?> pushRecord<T>(BuildContext context, String kind, int id, WidgetBuilder builder) async {
  final nav = Navigator.of(context);
  final name = recordRouteName(kind, id);
  final trail = nav.widget.observers.whereType<RecordTrail>().firstOrNull;
  if (trail != null && trail.has(name)) {
    if (DiscardGuard.anyDirty && !await confirmDiscard(context)) return null;
    if (nav.mounted) nav.popUntil((r) => r.settings.name == name);
    return null;
  }
  return nav.push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: RecordSiblings.take(id)),
      builder: builder,
    ),
  );
}

/// Opens the record that continues the work of the page it is called from, in that page's place: the flow moved on
/// (a quote became an order, a revision replaced a version), so Back must not return to the page the step just finished.
/// A record already open further down the stack is returned to instead, as in [pushRecord].
Future<T?> replaceRecord<T>(BuildContext context, String kind, int id, WidgetBuilder builder) async {
  final nav = Navigator.of(context);
  final name = recordRouteName(kind, id);
  final trail = nav.widget.observers.whereType<RecordTrail>().firstOrNull;
  if (trail != null && trail.has(name)) {
    if (DiscardGuard.anyDirty && !await confirmDiscard(context)) return null;
    if (nav.mounted) nav.popUntil((r) => r.settings.name == name);
    return null;
  }
  // The page that asks may be a dialog's or a card's context; only a record page on top is replaced.
  if (!(ModalRoute.of(context)?.isCurrent ?? false)) return pushRecord<T>(context, kind, id, builder);
  return nav.pushReplacement<T, void>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: RecordSiblings.take(id)),
      builder: builder,
    ),
  );
}
