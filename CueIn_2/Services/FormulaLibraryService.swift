import Foundation

// MARK: - FormulaLibraryService
/// Seeded formula library used by the Today formula mode.

enum FormulaLibraryService {
    private static let customSchedulesKey = "cuein.customSchedules.v1"
    private static let customBlockPresetsKey = "cuein.customBlockPresets.v1"
    private static var suppressSyncRecording = false

    static var allSchedules: [DayFormulaTemplate] {
        library + customSchedules()
    }

    /// User-saved block definitions only (not full schedules). See ``BlockTemplateLibrarySheet``.
    static func customBlockPresets() -> [DayFormulaBlockTemplate] {
        guard let data = UserDefaults.standard.data(forKey: customBlockPresetsKey) else { return [] }
        return (try? JSONDecoder().decode([DayFormulaBlockTemplate].self, from: data)) ?? []
    }

    /// Persists a reusable block preset. If one already exists with the same title (trimmed, compared case-insensitively), it is **replaced** so the library does not grow duplicate names.
    @discardableResult
    static func saveCustomBlockPreset(_ preset: DayFormulaBlockTemplate) -> Bool {
        var presets = customBlockPresets()
        let key = preset.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = presets.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) {
            let stableID = presets[index].id
            presets[index] = preset.withID(stableID)
        } else {
            presets.append(preset.copyWithNewID())
        }
        guard let data = try? JSONEncoder().encode(presets) else { return false }
        UserDefaults.standard.set(data, forKey: customBlockPresetsKey)
        recordSyncSnapshot()
        return true
    }

    /// Removes one user-saved block preset from the library.
    static func removeCustomBlockPreset(id: UUID) {
        var presets = customBlockPresets()
        presets.removeAll { $0.id == id }
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: customBlockPresetsKey)
        recordSyncSnapshot()
    }

    static func customSchedules() -> [DayFormulaTemplate] {
        guard let data = UserDefaults.standard.data(forKey: customSchedulesKey) else { return [] }
        return (try? JSONDecoder().decode([DayFormulaTemplate].self, from: data)) ?? []
    }

    /// Bundled + user schedules. Names are unique in the library (case-insensitive, trimmed).
    static func existingScheduleConflictingWithName(
        _ rawName: String,
        excludingScheduleID: UUID?
    ) -> DayFormulaTemplate? {
        let key = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return allSchedules.first { schedule in
            if let excludingScheduleID, schedule.id == excludingScheduleID { return false }
            return schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }
    }

    /// Picks a display name that does not collide with ``allSchedules`` (excluding one id when renaming that row).
    static func uniquedScheduleDisplayName(startingWith base: String, excludingScheduleID: UUID?) -> String {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = root.isEmpty ? "Untitled schedule" : root
        if existingScheduleConflictingWithName(stem, excludingScheduleID: excludingScheduleID) == nil {
            return stem
        }
        var index = 2
        while index < 10_000 {
            let candidate = "\(stem) \(index)"
            if existingScheduleConflictingWithName(candidate, excludingScheduleID: excludingScheduleID) == nil {
                return candidate
            }
            index += 1
        }
        return stem + " " + UUID().uuidString.prefix(6)
    }

    @discardableResult
    static func saveCustomSchedule(_ schedule: DayFormulaTemplate) -> Bool {
        if existingScheduleConflictingWithName(schedule.name, excludingScheduleID: schedule.id) != nil {
            return false
        }
        var schedules = customSchedules()
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }

        guard let data = try? JSONEncoder().encode(schedules) else { return false }
        UserDefaults.standard.set(data, forKey: customSchedulesKey)
        recordSyncSnapshot()
        return true
    }

    /// Removes one user-saved day formula from the library (bundled templates are not stored here).
    static func removeCustomSchedule(id: UUID) {
        var schedules = customSchedules()
        schedules.removeAll { $0.id == id }
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: customSchedulesKey)
        recordSyncSnapshot()
        Task { @MainActor in
            TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
        }
    }

    /// Removes user-created day formulas and saved block presets (bundled templates stay on disk in code).
    static func clearUserSavedTemplates() {
        UserDefaults.standard.removeObject(forKey: customSchedulesKey)
        UserDefaults.standard.removeObject(forKey: customBlockPresetsKey)
        recordSyncSnapshot()
    }

    static func syncPayload() -> [String: String] {
        let defaults = UserDefaults.standard
        return [
            "custom_schedules": defaults.data(forKey: customSchedulesKey)?.base64EncodedString() ?? "",
            "custom_block_presets": defaults.data(forKey: customBlockPresetsKey)?.base64EncodedString() ?? ""
        ]
    }

    static func applySyncPayload(_ payload: [String: String]) {
        suppressSyncRecording = true
        let defaults = UserDefaults.standard
        applyBase64Payload(payload["custom_schedules"], key: customSchedulesKey, defaults: defaults)
        applyBase64Payload(payload["custom_block_presets"], key: customBlockPresetsKey, defaults: defaults)
        suppressSyncRecording = false
        TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
    }

    private static func applyBase64Payload(_ value: String?, key: String, defaults: UserDefaults) {
        guard let value, !value.isEmpty, let data = Data(base64Encoded: value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func recordSyncSnapshot() {
        guard !suppressSyncRecording else { return }
        Task { @MainActor in
            CueInSyncRuntimeBridge.shared.recordFormulaLibrarySnapshot()
        }
    }

    static let library: [DayFormulaTemplate] = [
        DayFormulaTemplate(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            name: "Productive Weekday",
            symbol: "bolt.fill",
            summary: "A balanced workday with a clean ramp into deep focus and a steady finish.",
            targetDurationMinutes: 600,
            rules: [
                "Give deep work high priority before noon.",
                "Keep admin shallow and short."
            ],
            blocks: [
                DayFormulaBlockTemplate(
                    title: "Morning Routine",
                    type: .routine,
                    durationMinutes: 45,
                    flowMode: .blocking,
                    tasks: [
                        DayTask(title: "Hydrate & stretch", isPrimary: true),
                        DayTask(title: "Journal priorities")
                    ],
                    isRepeatable: true
                ),
                DayFormulaBlockTemplate(
                    title: "Deep Work",
                    type: .focus,
                    durationMinutes: 150,
                    flowMode: .blocking,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Admin Reset",
                    type: .focus,
                    durationMinutes: 40,
                    flowMode: .flowing,
                    taskSource: .executionFill,
                    fillRule: nil,
                    tasks: [],
                    isRepeatable: false,
                    pinsToClock: true,
                    fixedClockMinutesFromDayStart: 13 * 60 + 30,
                    schedulingPriority: nil,
                    compactPresentation: false
                ),
                DayFormulaBlockTemplate(
                    title: "Second Focus Window",
                    type: .focus,
                    durationMinutes: 120,
                    flowMode: .blocking,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Training",
                    type: .routine,
                    durationMinutes: 75,
                    flowMode: .blocking,
                    tasks: [
                        DayTask(title: "Strength or cardio", isPrimary: true),
                        DayTask(title: "Cool down")
                    ]
                ),
                DayFormulaBlockTemplate(
                    title: "Review and Shutdown",
                    type: .mini,
                    durationMinutes: 50,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Log outcomes"),
                        DayTask(title: "Plan tomorrow")
                    ]
                )
            ]
        ),
        DayFormulaTemplate(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            name: "Creator Sprint",
            symbol: "sparkles",
            summary: "Long creative windows with fewer switches and deliberate capture points.",
            targetDurationMinutes: 540,
            rules: [
                "Capture ideas before context switching.",
                "Leave whitespace around output-heavy blocks."
            ],
            blocks: [
                DayFormulaBlockTemplate(
                    title: "Warm Start",
                    type: .routine,
                    durationMinutes: 30,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Reset desk"),
                        DayTask(title: "Define today's creative target", isPrimary: true)
                    ]
                ),
                DayFormulaBlockTemplate(
                    title: "Make",
                    type: .focus,
                    durationMinutes: 180,
                    flowMode: .blocking,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Walk and Capture",
                    type: .mini,
                    durationMinutes: 25,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Voice notes or rough sketches")
                    ]
                ),
                DayFormulaBlockTemplate(
                    title: "Refine",
                    type: .focus,
                    durationMinutes: 145,
                    flowMode: .blocking,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Admin Edge",
                    type: .mini,
                    durationMinutes: 35,
                    flowMode: .flowing,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Evening Reset",
                    type: .routine,
                    durationMinutes: 45,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Tidy outputs"),
                        DayTask(title: "Mark next entry point")
                    ]
                )
            ]
        ),
        DayFormulaTemplate(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            name: "Recovery Reset",
            symbol: "heart.text.square.fill",
            summary: "A lighter day that still keeps structure without forcing velocity.",
            targetDurationMinutes: 480,
            rules: [
                "Energy first, intensity second.",
                "Keep the day soft but intentional."
            ],
            blocks: [
                DayFormulaBlockTemplate(
                    title: "Slow Morning",
                    type: .routine,
                    durationMinutes: 60,
                    flowMode: .blocking,
                    tasks: [
                        DayTask(title: "Mobility and breakfast", isPrimary: true),
                        DayTask(title: "No phone for the first stretch")
                    ]
                ),
                DayFormulaBlockTemplate(
                    title: "Light Admin",
                    type: .mini,
                    durationMinutes: 45,
                    flowMode: .flowing,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Walk",
                    type: .mini,
                    durationMinutes: 35,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Outside without headphones", isPrimary: true)
                    ]
                ),
                DayFormulaBlockTemplate(
                    title: "Focused Hour",
                    type: .focus,
                    durationMinutes: 90,
                    flowMode: .blocking,
                    taskSource: .executionFill
                ),
                DayFormulaBlockTemplate(
                    title: "Restore",
                    type: .routine,
                    durationMinutes: 90,
                    flowMode: .blocking,
                    tasks: [
                        DayTask(title: "Workout or stretch"),
                        DayTask(title: "Cook something real")
                    ],
                    isRepeatable: true
                ),
                DayFormulaBlockTemplate(
                    title: "Shutdown",
                    type: .mini,
                    durationMinutes: 40,
                    flowMode: .flowing,
                    tasks: [
                        DayTask(title: "Review the day"),
                        DayTask(title: "Set tomorrow's anchor")
                    ]
                )
            ]
        ),
        DayFormulaTemplate(
            id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
            name: "Test day (empty blocks)",
            symbol: "square.dashed",
            summary: "Dummy schedule for trying layouts and the running day—each block is blank so you can add tasks yourself.",
            targetDurationMinutes: 370,
            rules: [
                "Blocks are intentionally empty. Add tasks when you start the day or open a block."
            ],
            blocks: [
                DayFormulaBlockTemplate(
                    title: "Morning routine",
                    type: .routine,
                    durationMinutes: 45,
                    flowMode: .flowing,
                    tasks: []
                ),
                DayFormulaBlockTemplate(
                    title: "Study",
                    type: .focus,
                    durationMinutes: 90,
                    flowMode: .blocking,
                    tasks: []
                ),
                DayFormulaBlockTemplate(
                    title: "Lunch",
                    type: .mini,
                    durationMinutes: 45,
                    flowMode: .flowing,
                    tasks: []
                ),
                DayFormulaBlockTemplate(
                    title: "Work",
                    type: .focus,
                    durationMinutes: 120,
                    flowMode: .blocking,
                    tasks: []
                ),
                DayFormulaBlockTemplate(
                    title: "Admin & email",
                    type: .mini,
                    durationMinutes: 30,
                    flowMode: .flowing,
                    tasks: []
                ),
                DayFormulaBlockTemplate(
                    title: "Evening",
                    type: .routine,
                    durationMinutes: 40,
                    flowMode: .flowing,
                    tasks: []
                )
            ]
        )
    ]
}
