import Foundation

// MARK: - FormulaLibraryService
/// Seeded formula library used by the Today formula mode.

enum FormulaLibraryService {
    /// Bundled “Test day (empty blocks)” template — optional to hide from in-app lists (see Settings).
    static let bundledDummyTestDaySchemeID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!

    /// Canonical local storage for saved day layouts (TimeMaps).
    private static let customTimeMapsKey = "cuein.customTimeMaps.v1"
    /// Canonical local storage for reusable block presets (TimeMap blocks).
    private static let customTimeMapBlockPresetsKey = "cuein.customTimeMapBlockPresets.v1"
    /// Legacy keys — read until first write to canonical keys clears them.
    private static let legacyCustomSchedulesKey = "cuein.customSchedules.v1"
    private static let legacyCustomBlockPresetsKey = "cuein.customBlockPresets.v1"
    private static var suppressSyncRecording = false

    private static func storedTimeMapsData() -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: customTimeMapsKey), !data.isEmpty { return data }
        return defaults.data(forKey: legacyCustomSchedulesKey)
    }

    private static func storedTimeMapBlockPresetsData() -> Data? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: customTimeMapBlockPresetsKey), !data.isEmpty { return data }
        return defaults.data(forKey: legacyCustomBlockPresetsKey)
    }

    private static func clearLegacyScheduleKeysIfNeeded() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyCustomSchedulesKey)
        defaults.removeObject(forKey: legacyCustomBlockPresetsKey)
    }

    /// Built-in day layouts (starter schemes), respecting Settings for removed demo data and hidden dummy templates.
    static var bundledLibraryTemplates: [DayFormulaTemplate] {
        if CueInAppDataService.isGimmickDemoRemoved {
            return []
        }
        if UserDefaults.standard.bool(forKey: CueInAppDataKeys.hideBundledDummyTestDayTimeMap) {
            return library.filter { $0.id != bundledDummyTestDaySchemeID }
        }
        return library
    }

    static var allSchedules: [DayFormulaTemplate] {
        bundledLibraryTemplates + customSchedules()
    }

    /// User-saved block definitions only (not full TimeMaps). See ``BlockTemplateLibrarySheet``.
    static func customBlockPresets() -> [DayFormulaBlockTemplate] {
        guard let data = storedTimeMapBlockPresetsData(), !data.isEmpty else { return [] }
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
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: customTimeMapBlockPresetsKey)
        clearLegacyScheduleKeysIfNeeded()
        recordSyncSnapshot()
        return true
    }

    /// Removes one user-saved block preset from the library.
    static func removeCustomBlockPreset(id: UUID) {
        var presets = customBlockPresets()
        presets.removeAll { $0.id == id }
        guard let data = try? JSONEncoder().encode(presets) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: customTimeMapBlockPresetsKey)
        clearLegacyScheduleKeysIfNeeded()
        recordSyncSnapshot()
    }

    static func customSchedules() -> [DayFormulaTemplate] {
        guard let data = storedTimeMapsData(), !data.isEmpty else { return [] }
        guard let decoded = try? JSONDecoder().decode([DayFormulaTemplate].self, from: data) else { return [] }
        let normalized = Self.uniqueCustomDisplayNamesAgainstBundledAndPeers(decoded)
        if !Self.customTimeMapListsAreEquivalentByIdAndName(before: decoded, after: normalized) {
            Self.persistCustomSchedulesToStorage(normalized)
        }
        return normalized
    }

    /// Writes the full custom TimeMap list (used after collision repair and when saving one row).
    @discardableResult
    private static func persistCustomSchedulesToStorage(_ schedules: [DayFormulaTemplate]) -> Bool {
        guard let data = try? JSONEncoder().encode(schedules) else { return false }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: customTimeMapsKey)
        clearLegacyScheduleKeysIfNeeded()
        recordSyncSnapshot()
        return true
    }

    /// True when both lists are the same length, pair by index with matching `id`, and every name matches.
    private static func customTimeMapListsAreEquivalentByIdAndName(
        before: [DayFormulaTemplate],
        after: [DayFormulaTemplate]
    ) -> Bool {
        guard before.count == after.count else { return false }
        return !zip(before, after).contains { $0.id != $1.id || $0.name != $1.name }
    }

    /// Ensures each user TimeMap has a display name that does not collide with any **bundled** layout
    /// or another **custom** row (case-insensitive, trimmed). Rows are processed in storage order; the first
    /// row to claim a name keeps it; later collisions get suffixes such as `Name 2`, `Name 3`.
    private static func uniqueCustomDisplayNamesAgainstBundledAndPeers(_ schedules: [DayFormulaTemplate]) -> [DayFormulaTemplate] {
        let bundledKeys = Set(
            bundledLibraryTemplates.map {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        var taken = bundledKeys
        return schedules.map { sch in
            var next = sch
            let trimmed = sch.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            if !key.isEmpty, !taken.contains(key) {
                taken.insert(key)
                return next
            }
            let rootForSuffix = key.isEmpty ? "Untitled TimeMap" : trimmed
            var candidate = rootForSuffix
            var index = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(rootForSuffix) \(index)"
                index += 1
                if index > 10_000 {
                    candidate = "\(rootForSuffix) \(String(UUID().uuidString.prefix(8)))"
                    break
                }
            }
            taken.insert(candidate.lowercased())
            next.name = candidate
            return next
        }
    }

    /// Bundled + user schedules. New saves must not reuse a name already taken by any row (see ``customSchedules()`` repair for stored duplicates).
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
        let stem = root.isEmpty ? "Untitled TimeMap" : root
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

        return persistCustomSchedulesToStorage(schedules)
    }

    /// Removes one user-saved day formula from the library (bundled templates are not stored here).
    static func removeCustomSchedule(id: UUID) {
        var schedules = customSchedules()
        schedules.removeAll { $0.id == id }
        _ = persistCustomSchedulesToStorage(schedules)
        Task { @MainActor in
            TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
        }
    }

    /// Removes user-created day formulas and saved block presets (bundled templates stay on disk in code).
    static func clearUserSavedTemplates() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: customTimeMapsKey)
        defaults.removeObject(forKey: customTimeMapBlockPresetsKey)
        defaults.removeObject(forKey: legacyCustomSchedulesKey)
        defaults.removeObject(forKey: legacyCustomBlockPresetsKey)
        recordSyncSnapshot()
    }

    static func syncPayload() -> [String: String] {
        let mapsB64 = storedTimeMapsData()?.base64EncodedString() ?? ""
        let blocksB64 = storedTimeMapBlockPresetsData()?.base64EncodedString() ?? ""
        return [
            "custom_timemaps": mapsB64,
            "custom_time_map_block_presets": blocksB64,
            "custom_schedules": mapsB64,
            "custom_block_presets": blocksB64,
        ]
    }

    static func applySyncPayload(_ payload: [String: String]) {
        suppressSyncRecording = true
        let defaults = UserDefaults.standard
        let mapsPayload = payload["custom_timemaps"] ?? payload["custom_schedules"]
        let blocksPayload = payload["custom_time_map_block_presets"] ?? payload["custom_block_presets"]
        applyBase64Payload(mapsPayload, key: customTimeMapsKey, defaults: defaults)
        applyBase64Payload(blocksPayload, key: customTimeMapBlockPresetsKey, defaults: defaults)
        clearLegacyScheduleKeysIfNeeded()
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
            id: bundledDummyTestDaySchemeID,
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
