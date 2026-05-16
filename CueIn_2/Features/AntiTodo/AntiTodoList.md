# Anti To‑do list (module)

## What it is

The **Anti To‑do list** is a short list of **things you are choosing not to do**: habits, traps, or impulses that tend to derail you. Naming them makes them easier to notice in the moment. It is a **protective** surface, not a productivity scoreboard.

## What it is not

- **Not a task list.** Items are not `TaskItem`s, do not sync with the Tasks tab, and do not enter Today’s execution pool or completion stats.
- **Not shaming.** Slips are normal; the list is a reminder of intention, not a record of failure.

## Optional time rules (clock windows)

Some avoidances only matter at certain **hours** (e.g. “no work email before 10:00”, “no doomscroll after 22:00”). Those are **not** task deadlines—they are **local clock rules** that describe when you want extra vigilance.

Supported shapes:

- **Avoid until…** — the risky window is **from midnight up to** the chosen time (e.g. no email before 10:00 → rule is “on” from 00:00 until 09:59).
- **Avoid from… onward** — the risky window **starts** at the chosen time through the end of the day (e.g. no scrolling from 22:00).

Each rule can apply **every day**, **weekdays only**, or **weekends only**. Rules use the device’s **local time zone** and do not sync across devices (same as the rest of this module).

The list shows a subtle **“Now”** pill when a rule is active at the current moment so the screen stays honest without nag notifications.

## Design principles (v1)

- **One screen, one job:** scan the list, add an avoidance, edit or remove it.
- **Calm, minimal:** same card rhythm and spacing as the rest of CueIn; **reddish** accents signal “caution / not this” without loud alarm chrome.
- **Small edit surface:** title, optional time rule, delete—no projects, tags, or task-style metadata.

## v1 behavior

- **Add:** New entries are inserted at the **top** of the list. There is **no reorder** in v1.
- **Persistence:** Local only (`UserDefaults` + JSON). No cloud sync yet.

## Future ideas (not v1)

- Optional reorder or sections.
- Gentle “slip” logging without judgment.
- Sync via Supabase if the product needs cross-device continuity.
