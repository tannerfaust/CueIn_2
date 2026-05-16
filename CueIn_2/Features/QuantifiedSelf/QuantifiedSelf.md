# Quantified Self (tab) — product & architecture plan

## What it is

**Quantified Self** is a dedicated surface for **logging and reviewing personal measurements** that matter to you: coffee, water, sleep hours, mood, pain level, workouts, screen time, supplements—anything you want to count, rate, or note over time.

It is **intention-first logging**, not analytics for its own sake. The tab answers:

- “What did I actually do / feel / consume today?”
- “How does this habit or routine correlate with my week?”

It complements **Stats**, which today skews toward **task and day execution** summaries (completion, time allocation, trends). Quantified Self is **user-defined telemetry**: you choose the dimensions, the granularity, and optional links back to the rest of CueIn.

---

## Relationship to other areas

| Area | Role | Overlap / boundary |
|------|------|---------------------|
| **Stats** | Aggregate interpretation of work and time in the app | Stats may *surface* derived signals later (e.g. “logged sleep vs task completion”); Quantified Self owns **definitions, raw entries, and daily capture UX**. |
| **Today** | Execution and “now” | Today stays focused on blocks and tasks; Quantified Self can **deep-link** to a task or block for context, not replace the schedule. |
| **Tasks** | `TaskItem` work graph | Optional **link** from a metric entry or metric definition to a task (e.g. “Meditation” task ↔ “Minutes meditated” metric). |
| **Hub / Goals** | Direction, milestones | Goals may declare **success metrics** in prose today; later, a goal could reference a **metric definition ID** for measurable targets. |
| **Hub / Routines** (placeholder) | Repeatable systems | Future: routine completion could auto-suggest or auto-log a related metric. |
| **Anti To‑do** | Protective “not doing” list | Optional link for awareness (“when I log >N coffees, show anti-pattern reminder”)—**later**, not v1. |

---

## Design principles (aligned with `Style_Guide.md`)

- **One screen, one job** — primary tab screen = **today’s log**: scan, tap, done. Trends and library live behind **one obvious step** (segment control or toolbar), not competing headers.
- **Cards as the main container** — each **tracker** (metric definition + today’s value) is a calm card: title, optional icon, today’s control, subtle secondary line (yesterday / 7-day hint).
- **Bottom sheets for creation and editing** — add tracker, pick template, adjust type, link entities: all **sheet-first** to preserve context (`Style_Guide` §6).
- **Chips / pills** — filters (All / Body / Work / Social), unit tags, “linked” badges.
- **Minimal chrome** — default view shows **only active trackers** for the selected day; archive or hide inactive definitions without deleting history.
- **Dark-first, glass family** — same `CueInCard`, typography scale, spacing grid (4 pt), and tab bar language as the rest of the app.
- **Empty state** — short explanation + **“Add your first tracker”** + 2–3 template chips (e.g. Coffee, Water, Sleep) (`Style_Guide` §13).

---

## Core concepts (data model, conceptual)

### 1. Metric definition (the “tracker”)

Something the user wants to measure over time.

- **Identity** — stable `id` (UUID).
- **Presentation** — title, optional SF Symbol, optional color accent (restrained).
- **Value kind** (extensible enum) — e.g.:
  - **Count** (integer ≥ 0) — cups of coffee, glasses of water.
  - **Scale** (integer range, e.g. 1–5 or 1–10) — mood, energy, pain.
  - **Duration** (minutes or seconds) — sleep, walk, focus.
  - **Amount** (decimal + **unit**) — km, kg, L; preset units + custom label.
  - **Boolean** — did / did not (e.g. “Took vitamins”).
  - **Note-only** (optional text) — free journal line attached to the day (use sparingly; still one card).
- **Aggregation defaults** — how to roll up for week/month views: sum, average, max, min, last value, streak-friendly boolean.
- **Cadence hint** (optional) — “per day”, “per session”; v1 can treat everything as **per calendar day** in the user’s locale.
- **Visibility** — pinned to home row vs library-only.
- **Links** — zero or more **entity references** (see below) *defining* default context (e.g. this metric is “about” this recurring task).

### 2. Metric entry (the “log”)

A concrete value for a definition on a **day** (v1: calendar date; future: optional time-of-day for intra-day series).

- `definitionID`, `calendarDate`, `value` (polymorphic or tagged union in code), optional `note`.
- **Links** — optional list of **entity references** for this specific log (“logged after block X”, “ tied to task completion”).

### 3. Entity reference (scalable linking)

To stay **scalable and linkable** across modules, use a small **discriminated reference** everywhere (definitions and entries):

- `kind`: e.g. `task`, `goal`, `dayBlock`, `project`, `field`, `antiTodo`, `metricDefinition` (self-reference for grouping), …
- `id`: UUID (or string id where the domain already uses strings—match each store’s native id type).

**Rules:**

- References are **optional** and **non-owning**: deleting a task does not delete metric history; links become **dangling** and UI shows “Unresolved link” or hides the chip.
- **Resolve in the presentation layer** (view model) by asking `TasksStore`, `GoalStrategyStore`, etc.—avoid hard dependencies from domain structs to every feature type.

This matches how CueIn already treats **identity** in `TaskItem` and goals: stable ids + stores as source of truth.

---

## UX: adding and choosing inputs

### Path A — Template gallery (fastest)

Bottom sheet **“Add tracker”** → sections: **Lifestyle**, **Body**, **Mind**, **Work** (examples only).

- Tap **Coffee** → creates a **Count** definition, title “Coffee”, icon `cup.and.saucer.fill`, default stepper +1 per tap.
- User can still open **Edit** to rename, change max, or add a link.

### Path B — Custom metric (power user, still simple)

**“Custom…”** → short wizard: **Name → Type → (optional) unit → (optional) link to task/goal** → save.

### Path C — Duplicate from existing

Long-press or context menu on a definition → **Duplicate** (new id, same shape).

### Daily logging interaction (minimal taps)

Per **value kind**, optimize the **default control** on the card:

| Kind | Primary control on card |
|------|-------------------------|
| Count | Large **+** / optional **−**; optional “N” display; haptics on increment. |
| Scale | Horizontal **segmented** or discrete slider; show labels only at ends. |
| Duration | Stepper or preset chips (15 / 30 / 60); detail sheet for exact time. |
| Boolean | Single **toggle** or checkmark. |
| Amount | Numeric field collapsed; tap row to open sheet if needed. |

**Undo** — snackbar or lightweight toast (CueIn’s existing toast center if appropriate) for accidental +1.

---

## Tab structure (information architecture)

Suggested **two-segment** top control (same typography as other tabs):

1. **Today** — date strip or simple **previous / today / next** + list of tracker cards + **Add** in toolbar.
2. **Insights** (or **Trends**) — one card per metric: sparkline or weekly total, tap → detail (read-only first).

**Navigation bar** — title **“Quantified”** or **“Self”** (product naming pass); trailing **⋯** for import/export (future), units, data retention.

**FAB / global +** — when this tab is active, plus menu includes **“Log metric”** / **“New tracker”** (mirror pattern from other tabs).

---

## Navigation integration (`AppTab`)

Today the shell allows **up to 5 visible tabs** (`AppTab.maximumVisibleTabs`), with **Hub** forced present and user-customizable order (`editableTabs`).

Adding this feature implies:

1. New case, e.g. `quantifiedSelf`, with `label`, `icon` / `iconInactive`, and inclusion in `editableTabs`.
2. **Default tab set** is a product decision: either swap one default (e.g. keep Stats + add Quantified only via Hub / settings) **or** extend max slots (design + engineering tradeoff). Recommend **start as optional tab** users enable in tab customization so existing five-slot users are not disrupted.
3. `AppShellView` **tab content** switch + **FAB overflow** actions for this tab.
4. When shipped, update **`Style_Guide.md` §4** tab list copy so design doc matches the product (currently lists four names; code already allows more—align on purpose).

**Shipped wiring (shell + Hub):**

- **`AppTab.quantifiedSelf`** — tab bar label **Measures** (`quantifiedSelf` raw value for persistence).
- **`editableTabs`** — includes `.quantifiedSelf`, so **Hub → Settings → Navbar layout** lists it under **Add** when it is not already in the bar (same flow as Anti To‑do, Goals, etc.).
- **Hub → Tools** — **Measures** tile (`HubToolDefinition` id `quantifiedSelf`) opens the same `QuantifiedSelfView` in a full-height sheet with **Done** to dismiss.
- **Default bottom bar** — unchanged (five slots); users opt in via Navbar layout.

---

## Discovery in the app (implemented)

| Entry | What happens |
|--------|----------------|
| **Hub → Measures** (Tools grid) | Full-screen sheet with `QuantifiedSelfView` and a **Done** button. |
| **Hub → Settings → Navbar layout → Add → Measures** | Adds **Measures** to the floating tab bar (when fewer than five tabs are selected). |
| **Tab bar → Measures** | Same `QuantifiedSelfView` as the root of that tab. |
| **Global +** while on Measures | Opens the **New tracker** sheet (same as the toolbar +). |

---

## Shipped behavior (v1 code)

Aligned with common self-tracking UX guidance: **low-friction capture**, **templates**, **clear per-day context**, and **optional links** so Measures stays honest about “why this number exists.”

- **Persistence:** `MeasureStore` (`UserDefaults` + JSON), cleared on **Erase everything** with other local modules.
- **Trackers:** `MeasureDefinition` with `MeasureKind` — **count** (± stepper), **scale** (1…N chips or slider when N is large), **boolean**, **duration** (minute presets + clear).
- **Templates:** Coffee, water (default target 8), mood, sleep, energy, exercise, meditation, reading, walk — plus **Custom** (name + kind + scale top when relevant).
- **Day axis:** Previous / next local day, headline (Today / Yesterday / …), `yyyy-MM-dd` key for all logs.
- **Trend:** Seven-day micro-sparkline per tracker (normalized by kind).
- **Links:** Edit tracker → optional **Related task** / **Related goal** pickers (resolved titles on the card; links survive independently of store order).
- **Shell:** `Notification.Name.cueInShowAddMeasureTracker` wires the floating **+** on the Measures tab.

Future (not v1): HealthKit import, CSV export, automation from Today/tasks, richer charts, sync.

---

## Technical architecture (implementation sketch)

### Layers

| Layer | Responsibility |
|--------|----------------|
| **Domain** | `MetricDefinition`, `MetricEntry`, `MetricValue`, `CueInEntityRef` (Codable), enums for `MetricValueKind`, `Aggregation`. |
| **Persistence** | `QuantifiedSelfStore` (Observable), JSON + `UserDefaults` or file in app support—**same pattern as Anti To‑do** until sync exists. |
| **Features / UI** | `QuantifiedSelfView`, cards, sheets (`AddMetricSheet`, `EditMetricSheet`, `MetricTrendCard`). |
| **Cross-feature** | Protocol or small **LinkResolver** that maps `CueInEntityRef` → title + icon + navigation action (open task sheet, goal route, etc.). |

### Events (future)

- `NotificationCenter` or async stream for **“metric logged”** so Stats or Today can subscribe without tight coupling.
- Optional: **Automation hooks** — “when task X completed → increment metric Y” (v2+).

### Testing

- Pure aggregation tests on entries.
- Migration tests when adding new `MetricValueKind` cases.

---

## Phased roadmap

### Phase 1 — MVP (ship value early)

- Definitions: **count**, **scale**, **boolean**.
- Entries: **per calendar day**, one aggregate value per definition per day (simplest merge: last write wins, or sum for count—**product rule**: count **sums** intraday taps; scale **last**).
- UI: **Today** list + **Add** sheet + template chips.
- Persistence: local store only.
- Links: **optional** `CueInEntityRef` on definition only (display chip; tap navigates if resolvable).

### Phase 2 — Depth

- **Duration** and **amount + unit**.
- **Insights** segment with weekly sparklines.
- Links on **individual entries**.
- Export (CSV) from ⋯ menu.

### Phase 3 — Ecosystem

- Integrations (HealthKit, etc.) as **import pipelines**, not mixed into core model until stable.
- Goal ↔ metric targets (“sleep ≥ 7h average this week”).
- Routines / Today automation.

---

## Open questions (to resolve before build)

1. **Naming in UI** — “Quantified Self” is accurate but long for a tab; consider **“Measures”**, **“Trackers”**, or **“Body”** for the bar label with subtitle on screen.
2. **Intraday vs daily** — v1 daily is simpler; intraday changes the charting model.
3. **Privacy** — health-adjacent data: local-only until a formal sync/security story exists.
4. **Stats consolidation** — long-term, should some Stats cards be **fed only from** this store? Prefer **single source of truth** for user metrics to avoid duplication.

---

## Summary

Quantified Self is a **calm, card-based daily logging tab** with **typed metrics**, **template-driven onboarding**, and a **reference-based linking model** to tasks, goals, and other blocks—implemented as a small domain + store + SwiftUI feature module, integrated into **`AppTab`** without crowding **Today** or replacing **Stats**. It follows **`Style_Guide.md`**: one primary job on first paint, sheets for complexity, chips for metadata, and progressive disclosure for trends.
