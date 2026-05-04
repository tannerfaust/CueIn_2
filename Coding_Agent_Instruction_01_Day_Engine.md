# CueIn — Coding Agent Instruction 01
## App Shell + View-Only Pages + Day Engine / Today Tab

## Goal of this task
Build the first real product frame for CueIn.

This task has **two objectives**:

1. Build the **full app shell** with all main pages present as views.
2. Build the **first real functional module**: the **Day Engine**, inside the **Today** tab.

Do not try to build the whole product logic yet. We need a strong, expandable first version that already feels like the real app.

---

## Product concept to keep in mind
CueIn is an adaptive productivity system for living deliberately.

It is not just a task manager.
It is not just a calendar.
It is not just a habit tracker.

The product is meant to help users:
- structure their days
- organize their work and life
- adapt when reality changes
- execute block by block
- see whether they are actually progressing

The heart of the product is the idea that a day should not just be a flat list of tasks.
A day should be a **structured frame made of blocks**, and those blocks get filled with tasks, repeated systems, and smaller units of work.

The system should feel like:
- a day frame
- with larger blocks
- smaller task units inside them
- repeatable structures where needed
- flexibility when the plan changes

That is the core of the Today tab.

---

## What to build in this task

### Build the full app shell
Create the full app structure with the 4 main tabs visible and navigable:
- **Today**
- **Tasks**
- **Stats**
- **Hub**

Also build the large floating **plus button** to the right of the bottom tab bar.

For this first task:
- all tabs must exist
- all tabs must open properly
- only **Today** needs meaningful logic and real internal structure
- **Tasks**, **Stats**, and **Hub** can be view-only placeholders for now, but they must feel intentional, not empty junk screens

Each placeholder screen should already look like a real part of the app and suggest future depth.

---

## Design direction to follow
Follow the existing CueIn design direction.

### Important design requirements
- dark-first interface
- rounded geometry
- premium, calm, minimal feeling
- **Apple Liquid Glass style** for bottom navigation and floating controls
- floating rounded bottom tab bar
- moving active selection area / capsule inside the tab bar
- large floating plus button visually belonging to the tab system
- card-based layout
- generous whitespace
- smooth and restrained motion
- bottom sheets preferred over hard context switching where appropriate

Do not over-design.
Do not add noisy decoration.
Do not make it feel generic or dashboard-heavy.

The app should feel modern, calm, glassy where it matters, and highly readable.

---

## App shell requirements

### Root structure
Build a root app container with:
- persistent bottom navigation
- 4 tabs
- floating plus button
- smooth tab switching animation

### Required pages
Create these root pages:

#### 1. Today
This is the main page and the only page that should have real product depth in this task.

#### 2. Tasks
View-only for now.
Should visually suggest:
- inbox
- project/group structure
- task organization
- upcoming work

But do not build full task logic yet.

#### 3. Stats
View-only for now.
Should visually suggest:
- progress
- summaries
- charts/cards
- quantified-self / tracking direction

But do not build deep stats logic yet.

#### 4. Hub
View-only for now.
Should visually suggest:
- planning
- formulas
- goals
- deeper modules
- settings / system-level areas

But do not build those features yet.

---

## The only real module in this task: Today / Day Engine

## Core idea
Today is not a flat to-do list.
It is a **structured day frame**.

The day is made of **blocks**.
Blocks contain:
- tasks
- smaller units of work
- repeated routines
- mini-blocks if needed

The user should feel that their day has shape.
Not just items.

### Conceptual model
Think of the day like this:
- the day is a timeline / frame
- that frame is divided into blocks
- blocks can be different types
- blocks hold execution content
- tasks live inside the block context, not as one giant undifferentiated list

The Today experience should answer:
- what is happening now?
- what block am I in?
- what belongs inside this block?
- what is next?

---

## Block model for the UI
Design the Today UI around block types.

### Main block types to support visually

#### 1. Focus / Work blocks
Larger blocks for meaningful work.
These should contain tasks.

Examples:
- Deep Work
- Admin
- Study
- Build Session

#### 2. Routine / Repeatable blocks
Blocks for repeated systems.
These may contain small checklists or repeated actions.

Examples:
- Morning routine
- Workout
- Evening reset

#### 3. Fixed blocks
Blocks that are more static or time-anchored.

Examples:
- Meeting
- Appointment
- Commute

#### 4. Mini-blocks
Smaller, lighter execution units inside or between larger blocks.
Use them visually as supporting pieces of the day.

Examples:
- quick admin burst
- break
- short review
- quick call

Do not overcomplicate the logic yet. The goal here is to establish the UI model and reusable components.

---

## Today screen requirements
Build the Today tab as the first real screen of the app.

### The main Today view should include
- top area with a **running line on top**
- current day context
- vertically structured day timeline
- blocks displayed as cards or framed timeline units
- clear distinction between current block, upcoming blocks, and later blocks
- visible tasks preview inside blocks where appropriate
- smooth scrolling and clean spacing

---

## Running line on top
Do not forget this.

The top of the Today screen must include a **live running line**.
Treat it as a thin, persistent top status strip / timeline indicator that gives the page motion and present-tense awareness.

Its job is to reinforce that the day is alive and moving.

For this first version, the running line should at least communicate:
- current time / progress through the day
- current block context
- live state feeling

It does not need to be technically complex yet, but it must exist visually and feel intentional.

---

## Suggested Today screen structure

### Top area
- running line
- day label / date
- short current-state summary

### Main content area
- vertical day timeline
- block cards arranged in time order
- current block should be visually strongest
- next block should be clearly visible
- later blocks should still be scannable

### Bottom area
- bottom navigation
- floating plus button

---

## Current block behavior
The current block should feel special.

It should visually show:
- block title
- time range
- block type
- tasks or mini-items inside it
- one primary action direction

The user should immediately understand:
- this is where I am
- this is what belongs here

Do not build deep task state systems yet, but do build the structure in a way that clearly supports it later.

---

## Task presentation inside blocks
Tasks inside Today should not feel like a second giant task screen.

The visual principle is:
- tasks belong to a block
- tasks are subordinate to block context
- the block is the frame; tasks are the fill

For now, support:
- task rows inside blocks
- primary task emphasis when needed
- smaller supporting items
- repeated / routine items for repeatable blocks

Keep this modular so later we can add:
- completion states
- AI arrangement
- dynamic reprioritization
- drag/drop or reassign flows
- subtasks and mini-block nesting

---

## Plus button behavior for this task
The plus button should exist and open a contextual create sheet.

For now, in **Today**, it should open a bottom sheet with visually present options such as:
- Add block
- Add task
- Add routine block
- Add quick item

These actions do not need full backend logic yet.
They do need to feel real and connected to the screen.

On the other tabs, the plus button can open simple placeholder action sheets appropriate to that section.

---

## What must be architecturally true from the start
Even though this is still early, the code must be structured as if the product will grow a lot.

### Required architectural direction
- modular feature folders
- shared app shell
- reusable design components
- reusable block components
- reusable task row components
- clear separation between UI and logic
- models defined cleanly enough to grow later
- no business logic buried directly inside large view files

### Build so we can later add
- full task engine
- AI task arrangement
- AI replanning
- formulas / repeatable day systems
- integrations
- stats logic
- sync
- notifications
- App Store-safe permissions and future services

---

## Suggested module breakdown for implementation

### App
- root app entry
- root navigation shell
- shared tab container
- floating plus button container

### Design System
- colors
- spacing
- typography helpers
- glass surfaces
- cards
- chips
- buttons
- bottom sheet components

### Features / Today
- Today screen
- running line component
- timeline view
- block card components
- current block highlight
- task-in-block components
- add-item sheet

### Features / Tasks
- placeholder Tasks page

### Features / Stats
- placeholder Stats page

### Features / Hub
- placeholder Hub page

### Models
- DayBlock
- BlockType
- DayTask
- MiniBlock or supporting item model if needed

### Services / State
Keep minimal for now, but structure it cleanly so fake/mock data can later become real services.

---

## Data approach for this task
Use mock data.
But the mock data should already resemble real product data.

The Today screen should be driven by structured mock models, not hardcoded random text everywhere.

Example kinds of data you should support in the model:
- block id
- title
- type
- start time
- end time
- state
- list of tasks
- repeatable flag
- optional mini-items

This matters because we will build on top of this immediately.

---

## Important implementation mindset
This task is not about finishing the product.
It is about creating a **real first vertical slice**.

That means:
- the app shell should already feel like the app
- the design language should already feel correct
- Today should already communicate the product idea clearly
- the architecture should not trap us later

Do not waste time trying to complete all logic.
Do not make throwaway UI.
Build the foundation properly.

---

## Deliverable expected from this task
A working CueIn prototype with:
- root app shell
- 4 tabs
- floating plus button
- correct visual direction
- intentional placeholder screens for non-Today tabs
- a real Today tab built around the Day Engine concept
- top running line
- day timeline
- block-based execution UI
- tasks visually living inside block structures
- code organized in a modular, expandable way

---

## Final reminder
The key thing to understand is this:

CueIn’s Today tab is not just a schedule.
It is not just a list.
It is a **structured day frame**.

Blocks are the main unit.
Tasks fill those blocks.
Mini-blocks and repeatable structures make the day feel alive and practical.

Build the UI so that this idea is obvious even before deeper logic arrives.
