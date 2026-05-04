import Foundation

// MARK: - MockDataService
/// Provides realistic sample day data for the Today screen.
/// Structured to be replaceable by real services later.

enum MockDataService {

    /// Generate a full sample day anchored to today's date.
    @MainActor
    static func sampleDay() -> [DayBlock] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }

        return [
            DayBlock(
                title: "Morning Routine",
                type: .routine,
                startTime: time(6, 30),
                endTime: time(7, 15),
                tasks: [
                    DayTask(title: "Hydrate & stretch", isRepeating: true, field: "Health", project: "Morning", folder: "Life"),
                    DayTask(title: "Journal — 3 priorities", isRepeating: true, field: "Health", project: "Morning", folder: "Life"),
                    DayTask(title: "Review today's blocks", isRepeating: true, field: "CueIn", project: "Planning", folder: "Product"),
                ],
                isRepeatable: true
            ),
            DayBlock(
                title: "Deep Work",
                type: .focus,
                startTime: time(7, 30),
                endTime: time(9, 30),
                tasks: [
                    DayTask(title: "Finish API integration", isPrimary: true, field: "CueIn", project: "iOS App", folder: "Engineering"),
                    DayTask(title: "Write unit tests for auth flow", field: "CueIn", project: "iOS App", folder: "Engineering"),
                    DayTask(title: "Review PR #247", field: "CueIn", project: "iOS App", folder: "Engineering"),
                    DayTask(title: "Update technical docs", field: "CueIn", project: "Docs", folder: "Engineering"),
                ]
            ),
            DayBlock(
                title: "Quick Admin",
                type: .mini,
                startTime: time(9, 30),
                endTime: time(9, 45),
                flowMode: .flowing,
                tasks: [
                    DayTask(title: "Clear inbox", field: "Operations", project: "Comms", folder: "Admin"),
                    DayTask(title: "Reply to Slack threads", field: "Operations", project: "Comms", folder: "Admin"),
                ]
            ),
            DayBlock(
                title: "Team Sync",
                type: .fixed,
                startTime: time(10, 0),
                endTime: time(11, 0),
                tasks: [
                    DayTask(title: "Prep standup notes", isPrimary: true, field: "Operations", project: "Team", folder: "Meetings"),
                    DayTask(title: "Share sprint progress", field: "Operations", project: "Team", folder: "Meetings"),
                    DayTask(title: "Discuss blockers", field: "Operations", project: "Team", folder: "Meetings"),
                ]
            ),
            DayBlock(
                title: "Build Session",
                type: .focus,
                startTime: time(11, 0),
                endTime: time(13, 0),
                tasks: [
                    DayTask(title: "Implement block card UI", isPrimary: true, field: "CueIn", project: "iOS App", folder: "Design System"),
                    DayTask(title: "Add timeline connector", field: "CueIn", project: "iOS App", folder: "Design System"),
                    DayTask(title: "Polish running line animation", field: "CueIn", project: "iOS App", folder: "Design System"),
                    DayTask(title: "Test on different devices", field: "CueIn", project: "iOS App", folder: "QA"),
                ]
            ),
            DayBlock(
                title: "Lunch Break",
                type: .mini,
                startTime: time(13, 0),
                endTime: time(13, 30),
                tasks: [
                    DayTask(title: "Step away from screen", isRepeating: true, field: "Health", project: "Recovery", folder: "Life"),
                ]
            ),
            DayBlock(
                title: "Study",
                type: .focus,
                startTime: time(13, 30),
                endTime: time(15, 0),
                tasks: [
                    DayTask(title: "Read chapter 5 — System Design", isPrimary: true, field: "Learning", project: "Systems", folder: "Study"),
                    DayTask(title: "Take notes on key patterns", field: "Learning", project: "Systems", folder: "Study"),
                    DayTask(title: "Practice 2 algorithm problems", field: "Learning", project: "Algorithms", folder: "Study"),
                ]
            ),
            DayBlock(
                title: "Short Review",
                type: .mini,
                startTime: time(15, 0),
                endTime: time(15, 15),
                flowMode: .flowing,
                tasks: [
                    DayTask(title: "Check task completion", field: "CueIn", project: "Planning", folder: "Product"),
                    DayTask(title: "Adjust remaining blocks", field: "CueIn", project: "Planning", folder: "Product"),
                ]
            ),
            DayBlock(
                title: "Workout",
                type: .routine,
                startTime: time(17, 0),
                endTime: time(17, 45),
                tasks: [
                    DayTask(title: "Warm-up — 5 min", isRepeating: true, field: "Health", project: "Training", folder: "Life"),
                    DayTask(title: "Strength training — 30 min", isPrimary: true, isRepeating: true, field: "Health", project: "Training", folder: "Life"),
                    DayTask(title: "Cool-down & stretch", isRepeating: true, field: "Health", project: "Training", folder: "Life"),
                ],
                isRepeatable: true
            ),
            DayBlock(
                title: "Evening Reset",
                type: .routine,
                startTime: time(18, 0),
                endTime: time(18, 30),
                tasks: [
                    DayTask(title: "Review the day's progress", isRepeating: true, field: "Health", project: "Evening", folder: "Life"),
                    DayTask(title: "Plan tomorrow's blocks", isRepeating: true, field: "CueIn", project: "Planning", folder: "Product"),
                    DayTask(title: "Wind-down routine", isRepeating: true, field: "Health", project: "Evening", folder: "Life"),
                ],
                isRepeatable: true
            ),
        ]
    }
}
