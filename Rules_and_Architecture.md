# CueIn — Rules and Architecture

## 1. Purpose
This document defines the engineering rules and architectural direction for CueIn.

Its goal is to keep the app:
- logical
- modular
- scalable
- AI-ready
- integration-ready
- App Store friendly
- fast to iterate on

This is not a low-level technical spec. It is the structural guide for how CueIn should be built.

---

## 2. High-Level Architecture Goals
CueIn should be built so that it can:
- start simple
- grow without rewrites
- support multiple usage depths, from simple day planning to a deeper adaptive system
- support iPhone first, while staying ready for Mac and other platforms later
- add AI features without turning the whole app into an AI dependency
- add third-party integrations without polluting the core product logic

The architecture should support both:
- a user who only wants an adaptive planner
- a user who wants the full system with tasks, stats, planning, and deeper structure

---

## 3. Core Architecture Principles

### 1. Shared core, flexible interface
CueIn should have one shared product core, with platform-specific presentation where needed.
The business logic should not depend on a specific screen layout.

### 2. Modular by feature
The app should be organized by product modules, not by random technical file types only.
Each major feature should have clear boundaries.

### 3. UI should stay thin
Views should render state and trigger actions.
They should not hold deep business logic, scheduling logic, or AI logic.

### 4. Business logic should be explicit
Core product behavior should live in clear services, engines, or domain-level components.
If a behavior matters to the product, it should not be hidden inside views.

### 5. AI is an enhancement layer, not the foundation
CueIn must work without AI.
AI should improve planning, task handling, adaptation, and insight generation, but core flows must always have deterministic non-AI behavior.

### 6. Integrations are adapters, not the core system
Third-party apps should connect through isolated integration layers.
The internal CueIn model should stay independent.

### 7. Privacy and trust are product features
Data handling, permissions, syncing, and AI usage should all be built in a way that can be explained clearly and pass App Store review without ambiguity.

---

## 4. Recommended System Shape
CueIn should be built in layers.

### Presentation Layer
Screens, navigation, view state, local UI interactions.

### Application Layer
User actions, use cases, orchestration, flow control between modules.

### Domain Layer
Core logic and product rules:
- day structure
- blocks
- tasks
- scheduling logic
- stats logic
- planning logic
- review logic
- adaptation logic

### Data Layer
Persistence, sync, caching, repositories, external data mapping.

### Integration Layer
AI providers, calendar providers, third-party task systems, notifications, wearables, and later external automations.

This keeps the product logic protected from UI churn and external API churn.

---

## 5. Product Modules
CueIn should be structured around product modules.

### Core visible modules
- **Today**
- **Tasks**
- **Stats**
- **Hub**

### Deeper core modules
- **Planning / Formulas**
- **Day Engine**
- **Adaptation / Replanning**
- **Review / Insight Engine**
- **Quantified Self**

### Platform and support modules
- **AI Layer**
- **Integrations Layer**
- **Notifications**
- **Sync**
- **Settings / Account / Permissions**

Each module should own its own UI, state handling, and application logic boundaries where possible.

---

## 6. Rules for Modularity

### Each module should:
- have a clear responsibility
- expose clean interfaces
- avoid direct knowledge of unrelated modules
- depend on shared models and services, not on other modules' private details

### Avoid:
- giant shared managers that know everything
- putting logic into random helper files
- tightly coupling AI or integrations directly into UI screens
- mixing persistence concerns directly into view code

### Preferred approach:
- shared domain models
- protocols / interfaces for services
- feature-level composition
- clear input/output boundaries

---

## 7. Rules for State and Logic

### State
State should be predictable and easy to trace.
Prefer explicit data flow over hidden side effects.

### Logic
If logic affects:
- scheduling
- task ranking
- replanning
- progress calculation
- stats
- AI suggestions

then it should live outside the view layer.

### Side effects
External calls should be isolated behind services or repositories.
That includes:
- AI requests
- sync
- calendar access
- notifications
- external task imports

---

## 8. AI Architecture Rules
CueIn should be built so AI can be added safely and cleanly.

### AI should be used for:
- adaptive planning assistance
- task organization help
- smart task suggestions
- schedule reshaping suggestions
- pattern summaries
- optional insight generation
- natural input parsing

### AI should not be used for:
- mandatory core navigation
- irreplaceable product logic
- hidden decisions the user cannot understand
- flows that must work offline or reliably every time without fallback

### AI rules
- AI must always have a fallback behavior
- AI calls must be isolated behind an AI service layer
- prompts and model-specific logic should not be scattered across the app
- model provider decisions should be replaceable later
- user-facing AI should feel practical, not theatrical

This keeps CueIn useful even if providers, pricing, or policies change.

---

## 9. Integration Architecture Rules
CueIn should support integrations, but the internal system must stay clean.

### Integration principles
- external tools map into CueIn, not the other way around
- integrations should be optional
- each integration should have its own adapter layer
- external schemas should be translated into internal models
- sync conflicts should be handled intentionally, not casually

### Likely future integrations
- calendars
- task tools
- note / planning tools
- health / wearable data
- AI providers

The internal product model should not be shaped around any one provider such as Notion, Todoist, or a specific AI API.

---

## 10. App Store Friendliness Rules
CueIn should be designed in a way that is easy to explain to Apple and easy for users to trust.

### Rules
- use official APIs and permission flows
- ask only for permissions that are clearly needed
- make AI behavior understandable
- do not hide paid AI dependencies behind unclear UX
- do not misrepresent automation as user action
- keep privacy explanations simple and honest
- keep data collection minimal and intentional
- keep subscription / premium boundaries clear if added later

### Product implication
The app should still feel fully useful without requiring suspicious levels of access.

---

## 11. Scalability Rules
CueIn should scale in product depth without collapsing in complexity.

### That means:
- new modules can be added without rewriting old ones
- AI features can grow without infecting the whole codebase
- more surfaces can be added later: Mac, iPad, widgets, watch, notifications
- data model can expand without breaking older flows
- simple users and deep users can coexist in the same product

The architecture should support gradual deepening, not force all users into full complexity from day one.

---

## 12. Suggested Project Structure
A clean structure should look something like this:

- `App/` — app entry, app shell, navigation, root composition
- `Core/` — shared design system, shared primitives, common utilities
- `Domain/` — core models and engines
- `Data/` — repositories, persistence, sync, storage
- `Features/Today/`
- `Features/Tasks/`
- `Features/Stats/`
- `Features/Hub/`
- `Features/Planning/`
- `Features/AI/`
- `Features/Integrations/`
- `Services/` — notifications, calendar, AI adapters, external APIs
- `Docs/` — internal product and architecture docs

The exact shape can evolve, but feature boundaries should remain clear.

---

## 13. What to Avoid Early
Do not build:
- one giant all-knowing store without boundaries
- a product fully dependent on AI from day one
- hardcoded assumptions around one task provider or one calendar provider
- UI logic that decides product behavior by itself
- an architecture that makes Mac support or integrations painful later
- a bloated abstraction system before the product proves itself

CueIn should stay clean, practical, and expandable.

---

## 14. Final Direction
CueIn should be built as a modular adaptive product with a strong shared core.

It should be:
- simple enough to ship early
- structured enough to grow safely
- flexible enough to support different user depths
- ready for AI and integrations without depending on them
- clean enough to remain understandable as the product expands

The architecture should protect the product from chaos the same way the product itself is meant to protect the user from chaos.
