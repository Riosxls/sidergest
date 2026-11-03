/// Web only: makes the browser ask before the tab is closed or reloaded while [hasUnsaved] says true. Elsewhere it does nothing.
void installUnloadGuard(bool Function() hasUnsaved) {}

void removeUnloadGuard() {}
