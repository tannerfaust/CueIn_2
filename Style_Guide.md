# CueIn — Style Guide

## 1. Purpose
This document defines the core UI/UX direction for CueIn.
It is intentionally short. Its role is to keep design and implementation aligned while leaving room for iteration.

CueIn should feel:
- clean
- calm
- modern
- clear
- premium
- light in interaction, even when the product is powerful underneath

The product should not feel crowded, overly decorative, or visually noisy.

---

## 2. Core UI Direction
CueIn uses a **mobile-first, clean, rounded, card-based interface**.

Primary visual references:
- **Apple Liquid Glass** for navigation surfaces and floating controls
- rounded, soft, layered UI
- clean dark interface with strong readability
- minimal clutter, clear spacing, and obvious hierarchy

The visual language should balance:
- softness and precision
- depth and restraint
- modern polish and practical usability

---

## 3. Product-Level Design Principles

- **One screen, one job** — each screen should focus on one primary purpose.
- **Context should be preserved** — use bottom sheets, overlays, and inline actions before sending users to entirely new screens.
- **Clarity over density** — reduce overload; show what matters first.
- **Cards are the main content container** — cards group content cleanly in limited mobile space.
- **Avoid double nesting** — do not place cards inside cards unless absolutely necessary.
- **Visual hierarchy should be obvious** — users should understand importance through size, position, and emphasis.
- **Interaction should feel alive** — transitions, tab changes, sheet presentation, and confirmations should feel smooth and intentional.
- **The interface should teach itself** — states, highlights, and containers should explain usage without heavy instruction.

---

## 4. Navigation Structure
CueIn has **4 primary tabs** and **1 global contextual action button**.

### Primary Tabs
- **Today**
- **Tasks**
- **Stats**
- **Hub**

### Bottom Navigation
The bottom navigation should:
- use a **Liquid Glass** treatment
- be rounded and floating
- feel like a premium translucent control surface
- clearly show the active tab through a moving selected area / capsule
- animate smoothly when switching between tabs

### Global Plus Button
A large **floating plus button** sits to the right of the tab bar.
It should:
- visually pair with the tab bar
- use the same Liquid Glass family
- feel like a primary quick-create action
- open context-specific actions depending on the current tab

The tab bar and plus button should feel like one family, not two unrelated components.

---

## 5. Layout Principles

### Mobile Layout
- Prefer a **single-column layout**.
- Use clear vertical rhythm.
- Keep margins generous enough for breathing room.
- Use cards and sections to break content into readable chunks.

### Page Composition
Most screens should follow this structure:
1. top bar / context header
2. primary content area
3. optional secondary sections
4. bottom navigation

### Content Rules
- Put the most important content near the top.
- Keep primary actions visible and obvious.
- Avoid overloading the first screen view.
- Use progressive disclosure: reveal detail when needed.

---

## 6. Core Components

### Cards
Cards are the main building block.
Use them for:
- blocks
- tasks
- stats summaries
- goals
- modules
- suggestions
- logs

Card rules:
- rounded corners
- clean internal spacing
- subtle separation from background
- no heavy borders
- no excessive shadow in dark mode

### Bottom Sheets
Bottom sheets are the preferred secondary interaction pattern.
Use them for:
- quick creation
- editing
- filters
- pickers
- templates
- contextual options

Bottom sheet rules:
- should preserve context
- can open at different heights
- should support drag-to-dismiss
- background should subtly scale or dim to emphasize depth

### Lists
Use lists when scannability matters.
Keep rows clean and consistent.
Use dividers sparingly.

### Chips / Pills
Use chips for:
- states
- tags
- filters
- counts
- lightweight labels

Keep chips subtle in dark mode.

### Buttons
Use a clear button hierarchy:
- **Primary** — strongest action
- **Secondary** — supporting action
- **Ghost / Tertiary** — low-emphasis action
- **Icon buttons** — utility or contextual actions

### Inputs
Inputs must always have clear states:
- default
- focused
- filled
- error
- disabled

---

## 7. Typography
Use **one sans-serif typeface only**.
Prefer Apple-native typography behavior for platform consistency.

### Typography Rules
- keep the type system tight
- use a limited number of sizes
- prioritize readability over stylistic flair
- large headings may use slightly tighter tracking
- dense screens should rely mostly on smaller, efficient text sizes

### Suggested Type Scale
Keep to roughly these levels:
- **Large Title** — key screen headers
- **Title** — section headers
- **Body** — default reading text
- **Secondary / Caption** — metadata, labels, timestamps

Do not let typography become visually noisy through too many weights or sizes.

---

## 8. Spacing and Grid
Use a **4-point spacing system**.
All spacing, padding, and sizing should be based on multiples of 4 where practical.

Guidelines:
- 4 / 8 / 12 / 16 / 20 / 24 / 32 are the main spacing steps
- internal card padding should stay consistent
- avoid cramped compositions
- whitespace is more important than forcing too much on screen

Use grid logic as support, not as a visible constraint.

---

## 9. Color and Appearance
CueIn should support **dark mode as a first-class experience**.

### Color Direction
- start with a restrained neutral base
- use one primary accent color
- use semantic colors clearly:
  - blue = action / trust
  - green = success / progress
  - yellow = warning / caution
  - red = danger / destructive state

### Dark Mode Rules
- avoid harsh contrast everywhere
- use lighter surfaces instead of strong shadows to create depth
- reduce border intensity
- keep secondary text softer than primary text
- keep chips and pills dimmer than the most important content

The UI should feel rich and readable, not glowing or harsh.

---

## 10. Iconography
Use simple, clean iconography.
Icons should:
- align visually with text
- be easy to recognize
- stay minimal and not overly decorative
- match the calm, modern system feel

For sizing, keep icons visually aligned to text line height where possible.

---

## 11. Motion and Interaction
Motion is important.
CueIn should feel polished through controlled, smooth motion.

### Key Motion Principles
- transitions should be soft and responsive
- tab selection should animate clearly
- bottom sheets should slide with depth
- contextual confirmations should feel lightweight
- animations should support understanding, not decoration

### Key Interaction Expectations
Support familiar mobile gestures where useful:
- swipe right to go back
- swipe down to dismiss sheets
- long press for contextual actions
- pull / swipe where it adds clarity

Micro-interactions should exist for:
- completing an action
- switching states
- creating or saving something
- moving between contexts

---

## 12. States and Feedback
Every interactive element should communicate state.

### Required States
- default
- active
- pressed
- disabled
- loading
- success
- error

Feedback should be immediate and clear.
The product should never leave the user wondering whether an action happened.

Use lightweight confirmation patterns when appropriate.

---

## 13. Empty States
Design empty states intentionally.

Use them to:
- explain what belongs here
- guide first action
- reduce intimidation
- suggest a next step

Empty states should feel useful, not dead.

---

## 14. Screen-Specific Notes for CueIn

### Today
- should feel focused and execution-centered
- emphasize current block / current priority
- use cards to structure the day
- hierarchy must answer: what is happening now?

### Tasks
- should feel organized and scannable
- support inbox, projects, and grouped task views
- avoid visually overwhelming list density

### Stats
- should feel clean and legible
- prioritize interpretation over raw density
- use cards and grouped visual summaries

### Hub
- should feel like a structured control center
- hold planning, goals, settings, deeper modules, and secondary areas

---

## 15. Platform Notes
CueIn is being built as a multiplatform product, but this guide is primarily **mobile-first**.

That means:
- mobile patterns lead
- Mac layouts can expand later
- the visual language should remain shared
- desktop should add space and flexibility, not become a different design system

---

## 16. Design Summary
CueIn’s UI should be:
- rounded
- glassy where it matters
- card-based
- dark-first
- calm and premium
- highly readable
- animation-aware
- context-preserving
- mobile-native
- visually restrained, not flashy

If a design decision makes the product feel more cluttered, more generic, or less calm, it is probably the wrong decision.
