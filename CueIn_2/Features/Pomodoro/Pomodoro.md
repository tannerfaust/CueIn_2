# Pomodoro (inside the **Focus** tab)

The Pomodoro timer is a **rhythm layer** inside CueIn’s unified **Focus** surface (`FocusTabView`): work / short break / long break cycles, optional phase-end notifications, and convenience toggles (screen awake, in-app “focus coach” sheet).

## Goals

- **Minimal chrome** when embedded — the Focus tab owns the page header; the timer section is labeled **Timer** and uses the same card + ring language as the rest of CueIn.
- **Reliable timing** — wall-clock end dates so backgrounding does not skew remaining time; `AppShellView` calls `PomodoroStore.refreshFromWallClockIfNeeded()` when the scene becomes active.
- **Hub entry** — Hub opens the **Focus** tab (not a separate “Pomodoro” tab name in the UI).

## Architecture

| Piece | Role |
|--------|------|
| `PomodoroPhase` | `work`, `shortBreak`, `longBreak` |
| `PomodoroStore` | `@MainActor` `@Observable` session state, tick loop, transitions, UserDefaults prefs |
| `PomodoroNotificationService` | Categories, permission, schedule/cancel phase-end notification |
| `PomodoroNotificationDelegate` | Foreground banners + notification actions |
| `PomodoroView` | `PomodoroViewStyle.standalone` (legacy full page) or `.embeddedInFocusTab` (inside Focus) |
| `PomodoroTimerRing` | Progress ring |

## Navigation

- Hub catalog id **`focus`** posts `Notification.Name.cueInOpenFocus`.
- `AppShellView` switches `selectedTab` to `.focus`.
- `AppTab.focus` can be pinned in **Settings → Navbar layout**.

## Notifications

- One pending request id (`pomodoro.phaseEnd`) is rescheduled whenever the phase schedule changes (identifier kept for compatibility with existing installs).
- Category `POMODORO_PHASE` exposes **Pause** and **Skip** when iOS surfaces notification actions.

## Related docs

- **Focus tab shell + soundscapes:** `FocusTabView.swift`, `FocusSoundscapeStore.swift`, `FocusSoundscapes.md`
- **Science of masking / beats:** `FocusSoundscapes.md` (citations + claim calibration)

## Future ideas

- Live Activities for Lock Screen.
- Per-session labels tied to Today blocks or tasks.
