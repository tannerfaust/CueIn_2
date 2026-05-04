# Today tab — modes and views

The Today tab is the **Day Engine** surface: one tab, multiple **presentations** (how the day is shown) and multiple **run modes** (how time is interpreted and advanced). This document tracks what exists today and what is planned so UI, planning logic, and future AI features stay aligned.

---

## Planned structure (high level)

| Layer | Purpose |
|--------|--------|
| **Schedule style** | `ClassicDayScheduleStyle` — e.g. clock-anchored *timed* day vs *timeless* duration-first day. |
| **View variant** | Layout and chrome for that style (timeline density, headers, controls). |
| **Planning engine** | `DayRunPlanning` — turns intent + blocks into concrete `startTime` / `endTime` (formula, manual, AI, …). |
| **Execution rules** | Per-block `BlockFlowMode` (blocking vs flowing) and `BlockState` derivation in `TodayViewModel`. |

New experiences should plug in at the right layer instead of hard-coding everything in a single view.

---

## 1. Classic — formula-based — timeless view

**Status:** Engine plus **Today UI**: tap the **⋯** (ellipsis) menu on the Today navigation bar → **Block based** → **Clock slots** or **Timeless**. For Timeless, use **Set up timeless run…** (or choosing Timeless opens the sheet) to set **End run** and **Start run**. While a timeless run is live, **Finish current block** appears in the same menu when a block is active. **Settings** opens a placeholder sheet for future preferences.

### What “timeless” means here

Blocks are not tied to a pre-printed calendar grid for the run. Each block still has a **nominal length** (minutes), derived from the template day or from the user’s edits. When the user **starts a run**, the app **materializes** a real timeline from **now** forward.

### What “formula-based” means here

The default planner is **`ProportionalWindowDayPlanner`**, implementing `DayRunPlanning`:

1. The user chooses **when the run should end** (`dayEnd` > now) — the **run window** is `[runStart, dayEnd]`.
2. At start, the view model **snapshots** each block’s nominal minutes (`timelessNominalMinutesByBlockID`) so later compress/stretch cycles do not lose the original weighting intent.
3. Planned blocks receive new `startTime` / `endTime` such that their **durations are proportional to those nominals** and the **last planned block ends exactly at `dayEnd`**.  
   - If the window is **shorter** than the sum of nominals, slices **compress** (same ratios, tighter clock).  
   - If the window is **longer**, slices **stretch** to absorb the slack.  
4. **Tasks stay inside their blocks**; the formula only moves time boundaries, not task ownership.

API surface (see `TodayViewModel`):

- `startTimelessRun(dayEnd:)` — main path when the user picks an end time.  
- `startTimelessDay()` — convenience: implicit `dayEnd = now + sum(nominal minutes)` (no end picker).  
- `finishActiveBlock()` — for **blocking** blocks (or early finish); **replans the tail** into the remaining `[now, timelessTargetDayEnd]` using the same nominal snapshot so the chosen day end stays the anchor.

### Blocking vs flowing (execution, not planning)

Each `DayBlock` has a `flowMode`:

- **Blocking** — the block can stay **active** past its planned `endTime` until the user finishes it; the next block does not start until prior blocks are done (or skipped).  
- **Flowing** — when clock time passes `endTime`, the block is treated as **completed** and the next eligible block can become active.

Planning (proportional window) and execution (blocking/flowing) are **orthogonal**: the planner assigns windows; `deriveBlockStates()` applies flow semantics.

### Extensibility (AI and other modes)

- **`DayRunPlanning`** is the seam for alternative strategies: same `DayRunPlanContext` in, updated `DayBlock` list + metadata out.  
- **`DayRunPlanningSource`** distinguishes `.formulaProportionalWindow`, future `.userManual`, `.externalAI`, etc., for logging and UI.  
- **`TodayViewModel`** accepts `init(dayRunPlanner:)` so tests or a future **AI planner** can swap implementations without rewriting the tab.

---

## 2. Classic — timed slots view

**Status:** Default today for `ClassicDayScheduleStyle.timedSlots`.

Blocks use fixed **wall-clock** `startTime` / `endTime`. State follows the real clock (`deriveTimedSlotBlockStates`). No user-chosen run window; the “shape” of the day is defined by those times.

*Future note:* subviews might still vary (density, focus on current block only, etc.) while keeping the same schedule style.

---

## 3. Other Today presentations (placeholder)

Additional tab-level or nested experiences (e.g. list-first day, stats-forward, minimal “now only”) are **not** specified here yet. When added, each should declare:

- Which **schedule style** it uses (if any).  
- Whether it uses **`DayRunPlanning`** or only static data.  
- How it maps to shared components under `Features/Today/Components/`.

---

## File map (Today feature)

| Area | Role |
|------|------|
| `Views/TodayView.swift` | Shell for the tab; wires subviews to `TodayViewModel`. |
| `TodayViewModel.swift` | Schedule style, timeless run lifecycle, delegates planning to `DayRunPlanning`. |
| `Services/DayRunPlanning/` | Protocol, context/result types, `ProportionalWindowDayPlanner`. |
| `Domain/Models/` | `DayBlock`, `DayTask`, `BlockFlowMode`, `ClassicDayScheduleStyle`, etc. |
| `Components/` | Timeline, cards, headers — mostly presentation; should stay agnostic to *which* planner ran when possible. |

---

*Last aligned with: formula timeless run + proportional window planner + tail replan on `finishActiveBlock`.*
