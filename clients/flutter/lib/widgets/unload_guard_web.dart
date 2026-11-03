import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Makes the browser ask before the tab is closed or reloaded while [hasUnsaved] says true.
void installUnloadGuard(bool Function() hasUnsaved) {
  globalContext.setProperty(
    'onbeforeunload'.toJS,
    ((JSObject event) {
      if (!hasUnsaved()) return;
      event.callMethod('preventDefault'.toJS);
      event.setProperty('returnValue'.toJS, ''.toJS);
    }).toJS,
  );
}

void removeUnloadGuard() => globalContext.setProperty('onbeforeunload'.toJS, null);
