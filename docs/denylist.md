# Denylist apps from the global toggle hotkey

## Context

The global toggle hotkey (`GlobalShortcutService` → `NavigationController::toggleWindow()`) currently fires unconditionally, regardless of which app is focused. The user hit a real problem on their macOS client: some app should never have the launcher pop over it when the hotkey is pressed. They want a per-app "exclude from hotkey" toggle, reusing the identifiers/patterns already used by the existing per-app enable/disable list in Settings, and — since macOS is the actual target platform — the keypress should be genuinely passed through to the focused app instead of just being silently swallowed.

Implementation happens on Linux (dev machine); the macOS-specific pass-through path will be verified by building natively on a Mac afterwards (cross-compiling isn't practical for this project — see prior discussion).

## Design summary

- Reuse the existing app entrypoint id (`EntrypointId{"applications", app->id()}`, same id used by the enable/disable toggle) as the denylist key — no new identifier scheme.
- Add a new per-entrypoint config flag `hotkey_excluded`, alongside the existing `enabled`/`shortcut`/`alias` fields, following the exact same storage/merge pattern.
- `GlobalShortcutService` gains `WindowManager` + `AppService` dependencies, tracks the focused app on `WindowManager::focusChanged`, and maintains a cheap cached `std::atomic<bool>` "toggle suppressed" flag — expensive lookups (window → wmClass → app id) happen once per focus change on the main thread, not per keypress.
- Backends gain an injectable activation gate they consult before acting. On macOS, where the shortcut is captured via a non-exclusive `CGEventTap`, the gate lets `handleKeyDown` return "not consumed" so the keystroke is genuinely delivered to the focused app — true pass-through, no synthetic re-injection needed. On X11/Windows, the OS-level grab (`XGrabKey`/`RegisterHotKey`) is exclusive so the physical keystroke can't be un-swallowed there; the gate still suppresses the *action* (today it always opens/closes the launcher — this is a strict improvement, not a regression).
- Settings UI: extend the existing per-app list (Applications section, `RootItemManager`-backed) with a second toggle, mirroring the enable/disable toggle end-to-end.

## Changes

### 1. Config (`src/server/src/config/config.hpp`)
Add one field to `ProviderItemData` (used as-is in both full and partial config, like `enabled`):
```cpp
struct ProviderItemData {
  std::optional<std::string> alias;
  std::optional<bool> enabled;
  std::optional<bool> hotkeyExcluded;   // new
  std::optional<std::string> shortcut;
  std::optional<glz::generic::object_t> preferences;
};
```
Glaze snake-cases this automatically (existing `SNAKE_CASIFY`/`ConfigTransformer` machinery), giving `hotkey_excluded` in the JSON.

### 2. `RootItemManager` (root-item-manager.hpp/.cpp)
- Add `bool hotkeyExcluded = false;` to `RootItemMetadata`.
- Add `bool setItemHotkeyExcluded(const EntrypointId &id, bool value);`, mirroring `setItemEnabled` (root-item-manager.cpp:270-273): `m_cfg.mergeEntrypointWithUser(id, {.hotkeyExcluded = value}); return true;`
- In `mergeConfigWithMetadata` (root-item-manager.cpp:638+), project `item.hotkeyExcluded.value_or(false)` into the metadata, same place `enabled` is projected today.

This gives the settings UI a read/write path consistent with the enable/disable toggle, and is a natural place to expose "is this app hotkey-excluded" for any other future consumer.

### 3. `GlobalShortcutService` (global-shortcut-service.hpp/.cpp)
- Add constructor deps `WindowManager &windowManager, AppService &appService` (both already constructed before `GlobalShortcutService` in `server.cpp`, per its existing local-variable ordering — pass by reference the same way `RootItemManager` is passed today; update the `server.cpp` construction call site and any header includes/forward-declares).
- New members:
  - `std::unordered_set<std::string> m_hotkeyExcludedAppIds;` — rebuilt in `reconcile()` by scanning `cfg.providers["applications"].entrypoints` for `hotkeyExcluded == true`, collecting the entrypoint keys (these are already app ids, `.desktop`-suffix-stripped on Linux / bundle id on macOS — same convention `AppRootItem::uniqueId()` uses).
  - `std::atomic<bool> m_toggleSuppressed{false};`
- New private slot `updateToggleSuppression()`, connected to `WindowManager::focusChanged`, and also invoked once at the end of `reconcile()` (so a config change re-evaluates immediately):
  - `auto win = m_windowManager.getFocusedWindow();` → if null, clear suppression.
  - else resolve `m_appService.findByClass(win->wmClass())` → if resolved, check `m_hotkeyExcludedAppIds.contains(app->id() with .desktop stripped)`; store into `m_toggleSuppressed`.
- Give the backend a way to consult this synchronously. Add to `AbstractGlobalShortcutBackend` (abstract-global-shortcut-backend.hpp):
  ```cpp
  void setActivationGate(std::function<bool(const QString &id)> gate) { m_gate = std::move(gate); }
  protected:
    std::function<bool(const QString &id)> m_gate; // returns true => suppress this activation
  ```
  In `GlobalShortcutService`'s constructor, after building `m_backend`:
  ```cpp
  m_backend->setActivationGate([this](const QString &id) {
    return id == QString::fromUtf8(TOGGLE_ID) && m_toggleSuppressed.load(std::memory_order_relaxed);
  });
  ```
  This keeps the gate reading a single atomic bool — safe to call from any thread, including the macOS tap thread.

### 4. Backend consultation of the gate
- **macOS** (`macos-global-shortcut-backend.cpp`, `handleKeyDown` ~256-310): when a binding matches, check the gate before doing the `QMetaObject::invokeMethod(..., Qt::QueuedConnection)` emit. If gated, return `false`/skip emit so `tapCallback` (~102-117) returns the original `event` unmodified — the OS delivers it to the focused app normally. This is the true pass-through path, made possible because this backend already uses a non-exclusive `CGEventTap` with an explicit consume/pass-through return value.
- **X11** (`x11-global-shortcut-backend.cpp`, `drainEvents` ~187-206): before `emit shortcutActivated(...)`, check the gate; skip the emit if gated. The physical key is still consumed by `XGrabKey` (unavoidable without synthetic replay via `XTestFakeKeyEvent`, out of scope here) but the launcher no longer toggles.
- **Windows** backend: same pattern at its `WM_HOTKEY` handling site.
- Wayland backend, if it has independent activation code: same pattern.

### 5. Settings UI
Extend the existing Applications settings list (backed by `ExtensionSettingsModel`, `src/server/src/qml/extension-settings-model.{hpp,cpp}`, rendered by the QML settings page under `src/server/src/qml/qml/`) with a second toggle column/action next to the existing enable/disable toggle:
- Mirror `ExtensionSettingsModel::setEnabled`/`setEnabledByEntrypointId` (extension-settings-model.cpp:138, 432) with `setHotkeyExcluded`/`setHotkeyExcludedByEntrypointId`, calling the new `RootItemManager::setItemHotkeyExcluded`.
- Mirror the `EnabledRole`/`enabled` model role plumbing (line ~66, ~275, ~311) with a `HotkeyExcludedRole`.
- Add the corresponding toggle control in the QML list delegate next to the existing enabled toggle, with a translated label (`qsTr("Exclude from hotkey")` or similar) and tooltip explaining the behavior, per the i18n rules in CLAUDE.md.
- Scope this toggle to the Applications provider only (it's meaningless for extension commands, which already have their own shortcuts) — follow whatever provider-type gating the QML/model already does for app-only affordances, if any exists; otherwise gate on `entrypointId.provider == "applications"`.

## Verification
- `make debug` on Linux: confirm it builds clean with the new config field, service deps, and gate plumbing.
- Manual test on Linux: mark an app "excluded from hotkey" in Settings, focus it, press the toggle hotkey — launcher should not open. Focus a different (non-excluded) app — hotkey should still work. Toggle the setting off — behavior reverts.
- Push and build natively on macOS (per earlier discussion — no cross-compile path). Repeat the same manual test there, additionally confirming the keypress is actually delivered to the focused app (e.g. bind the toggle shortcut to a combo the focused app also handles, and confirm the app reacts) to validate true CGEventTap pass-through, not just suppression.
- `make format` at the end per CLAUDE.md.
