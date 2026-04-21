# NotesCurator Agent Notes

## macOS Window Behavior

- Treat the macOS red close button as "close this window", not "hide the app" and not "quit the app".
- If the user closes the last main window, clicking the Dock icon should reopen the main app window without requiring a full quit and relaunch.
- Prefer native macOS reopen behavior for single-window apps. If a custom `App` or `NSApplicationDelegate` lifecycle is used, wire explicit reopen handling such as `applicationShouldHandleReopen` plus a scene-aware `openWindow(id:)` path.
- When changing macOS app shell behavior, verify the close, minimize, Dock reopen, and re-activation flow instead of only checking that the app launches.
