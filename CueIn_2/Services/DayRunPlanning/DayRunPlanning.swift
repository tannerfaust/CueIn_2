import Foundation

// MARK: - Day run planning (extensible)

/// Central extension point for **how** a run becomes a concrete timeline.
///
/// **Extending:** add fields to ``DayRunPlanContext`` (e.g. priorities, energy curve, natural-language
/// intent) and new ``DayRunPlanningSource`` cases; swap or compose planners in ``TodayViewModel``’s
/// injected ``DayRunPlanning`` implementation (formula today, AI/service tomorrow).
/// Implementations can be formula-based (fixed rules), user-driven, or supplied by AI / services.
/// Keep inputs and outputs value-oriented so plans can be cached, diffed, logged, or replaced remotely.
protocol DayRunPlanning {
    /// Produces a new schedule for the given indices only; other blocks are copied through unchanged.
    func makePlan(context: DayRunPlanContext) throws -> DayRunPlanResult
}

// MARK: - Provenance

/// Where a plan came from — useful for analytics, UI badges, and future AI pipelines.
enum DayRunPlanningSource: String, Codable, Sendable {
    /// Deterministic share of the wall window (current timeless “formula” mode).
    case formulaProportionalWindow
    /// Hand-edited or drag-adjusted (future).
    case userManual
    /// Generated externally (future LLM / recommender).
    case externalAI
}

// MARK: - Context / result

struct DayRunPlanContext: Sendable {
    /// Full ordered day; only ``plannedBlockIndices`` are rescheduled.
    var blocks: [DayBlock]
    /// Execution order; must be strictly increasing indices into ``blocks``.
    var plannedBlockIndices: [Int]
    var runStart: Date
    /// User-chosen end of the run window (last planned block ends here, modulo rounding fix).
    var targetEnd: Date
    /// Nominal block lengths in minutes, keyed by block id — preserves intent after earlier compress/stretch cycles.
    var nominalMinutesByBlockID: [UUID: Int]
    var planningSource: DayRunPlanningSource
}

struct DayRunPlanResult: Sendable {
    var blocks: [DayBlock]
    var metadata: DayRunPlanMetadata
}

struct DayRunPlanMetadata: Sendable {
    var planningSource: DayRunPlanningSource
    /// `targetEnd - runStart` in seconds (what the planner tried to fill).
    var windowDuration: TimeInterval
    /// Sum of nominal minutes for planned blocks (pre-scale mental model).
    var totalNominalMinutes: Double
}

// MARK: - Errors

enum DayRunPlanningError: Error, Equatable {
    case targetEndNotAfterRunStart
    case emptyPlan
    case invalidBlockIndex(Int)
}
