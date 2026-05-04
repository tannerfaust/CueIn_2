# CueIn — Modules

## Purpose of this document

This document defines the main product modules of CueIn in a simple way, so the product stays coherent as it grows.

The goal is not to describe every feature. The goal is to define the major functional parts of the product, what each one is responsible for, and how they connect.


---

## Module principles

- Modules should reflect real user jobs, not internal company language.
- Each module should have a clear responsibility.
- Adaptation must be treated as part of the core product, not as an edge case.
- The structure should support AI, integrations, and deeper automation without forcing a redesign.

---

## 1. Day Engine

### Purpose
The main execution module of the app.

### Responsibility
Help the user understand what is happening now, what block they are in, what tasks belong inside it, and how the day should adapt if reality changes.

### Core elements
- daily timeline
- current and upcoming blocks
- tasks inside blocks
- active block view
- block completion and quick status updates
- quick replan / move / delay actions

### Role in the product
This is where the product becomes real. All higher-level planning should eventually resolve into a usable Today experience.

---

## 2. Tasks

### Purpose
The work and responsibility management module.

### Responsibility
Store, organize, and manage the user’s tasks, projects, and incoming responsibilities before and during execution.

### Core elements
- inbox
- task lists
- projects
- task properties
- recurring tasks
- assignment into day blocks

### Role in the product
This module should ensure CueIn is not dependent on vague plans alone. It gives the product a real work layer that connects structure with execution.

---

## 3. Stats

### Purpose
The reflection, visibility, and measurement module.

### Responsibility
Show the user how they are actually living, performing, and progressing over time.

### Core elements
- planned vs actual
- time allocation
- productivity and consistency views
- quantified self logging
- trends and pattern visibility
- review summaries

### Role in the product
This module closes the loop. It turns activity into feedback and feedback into better decisions.

---

## 4. Hub

### Purpose
The deeper system module of the app.

### Responsibility
Hold the long-range and structural parts of the product that do not belong in direct execution.

### Core elements
- goals and direction
- formulas and templates
- planning tools
- routines
- AI tools
- integrations
- settings and profile-level controls

### Role in the product
Hub is the place where the user builds and manages the system behind daily execution.

---

## 5. Planning and Formula Layer

### Purpose
The structure-building layer of the product.

### Responsibility
Translate goals and intentions into reusable day and week structures.

### Core elements
- formulas
- day templates
- week structure
- reusable blocks
- planning rules
- task-to-block assignment logic

### Role in the product
This layer gives CueIn its system character. It is the bridge between direction and the actual day.

### Placement
This layer will mainly live inside **Hub** in early versions, even if later it may deserve more direct exposure.

---

## 6. Adaptation Layer

### Purpose
The recovery and responsiveness layer.

### Responsibility
Help the user stay functional when plans break, time shifts, priorities change, or energy drops.

### Core elements
- quick replanning
- block reshuffling
- task movement
- recovery suggestions
- preserving priority work during disruption

### Role in the product
This is one of CueIn’s defining capabilities. The system should not collapse when reality changes.

### Placement
This layer primarily appears inside **Today**, but depends on planning rules, task logic, and  AI support.

---

## 7. AI and Automation Layer

### Purpose
The intelligence and friction-reduction layer.

### Responsibility
Use AI only where it makes the product faster, clearer, or more adaptive.

### Core elements
- task organization assistance
- task-to-day suggestions
- formula suggestions
- replanning support
- pattern summaries
- future automation across connected tools

### Role in the product
AI should strengthen the product’s core loop, not distract from it. It must remain practical and grounded.

### Placement
This is a cross-product layer that touches Tasks, Today, Stats, and Hub.

---

## 8. Integration Layer

### Purpose
The external system connection layer.

### Responsibility
Connect CueIn with outside tools so the product can work as a real personal operating system instead of a closed island.

### Core elements
- calendar integrations
- task source integrations
- health and wearable data later
- sync across user devices

### Role in the product
This layer reduces fragmentation and makes CueIn more realistic for everyday use.

---

## Product structure summary

At product level, CueIn is built from four visible modules and several deeper system layers.

### Main user-facing modules
- Today
- Tasks
- Stats
- Hub

### Deeper system layers
- Planning and Formula Layer
- Adaptation Layer
- AI and Automation Layer
- Integration Layer

---

## Final note

The structure should stay simple:

- **Today** runs the day
- **Tasks** holds the work
- **Stats** shows the truth
- **Hub** holds the deeper system

Everything else should strengthen that loop rather than compete with it.
