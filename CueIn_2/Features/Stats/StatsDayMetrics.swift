import Foundation

// MARK: - StatsDayMetrics
/// Pure functions: Stats reads ``TodayViewModel`` + tasks but keeps layout types dumb.

struct StatsDaySnapshot: Equatable {
    /// 0…1 — schedule block completion when a formula day is running or stopped; otherwise today’s task ratio.
    var algorithmProgress: Double
    /// Short line under the algorithm ring.
    var algorithmCaption: String
    /// True when the score comes from a live or completed formula run.
    var algorithmUsesFormulaRun: Bool

    /// 0…1 — share of today’s awake window that has already passed (Apple “Move”-style fill).
    var awakeProgress: Double
    /// Human label for the awake ring (time left until sleep, etc.).
    var awakeCaption: String

    /// 0…1 — `TasksStore.todayTasks` completion.
    var todayTasksProgress: Double
    var todayTasksCaption: String
}

enum StatsDayMetrics {
    static func makeSnapshot(
        calendar: Calendar = .current,
        now: Date,
        viewModel: TodayViewModel,
        todayTasks: [TaskItem],
        wakeMinutesFromMidnight: Int,
        sleepMinutesFromMidnight: Int
    ) -> StatsDaySnapshot {
        let wake = StatsDisplayPreferences.clampWakeMinutes(wakeMinutesFromMidnight)
        let sleep = StatsDisplayPreferences.clampSleepMinutes(wakeMinutes: wake, sleepMinutes: sleepMinutesFromMidnight)

        let taskDone = todayTasks.filter(\.isCompleted).count
        let taskTotal = todayTasks.count
        let taskRatio = taskTotal > 0 ? Double(taskDone) / Double(taskTotal) : 0

        let algorithmTuple = algorithmScore(viewModel: viewModel, taskDone: taskDone, taskTotal: taskTotal, taskRatio: taskRatio)
        let awakeTuple = awakeRing(
            calendar: calendar,
            now: now,
            wakeMinutes: wake,
            sleepMinutes: sleep
        )

        let tasksCaption: String
        if taskTotal == 0 {
            tasksCaption = "No tasks on Today"
        } else {
            tasksCaption = "\(taskDone) of \(taskTotal) today’s tasks"
        }

        return StatsDaySnapshot(
            algorithmProgress: algorithmTuple.progress,
            algorithmCaption: algorithmTuple.caption,
            algorithmUsesFormulaRun: algorithmTuple.usesFormulaRun,
            awakeProgress: awakeTuple.progress,
            awakeCaption: awakeTuple.caption,
            todayTasksProgress: taskRatio,
            todayTasksCaption: tasksCaption
        )
    }

    private static func algorithmScore(
        viewModel: TodayViewModel,
        taskDone: Int,
        taskTotal: Int,
        taskRatio: Double
    ) -> (progress: Double, caption: String, usesFormulaRun: Bool) {
        if viewModel.dayEngineMode == .formulaBased, viewModel.hasFormulaRunStarted {
            let relevant = viewModel.blocks.filter { $0.state != .skipped }
            let denom = max(relevant.count, 1)
            let completed = relevant.filter { $0.state == .completed }.count
            let blockRatio = Double(completed) / Double(denom)

            let vmTaskTotal = viewModel.totalTaskCount
            let vmTaskRatio: Double
            if vmTaskTotal > 0 {
                vmTaskRatio = Double(viewModel.completedTaskCount) / Double(vmTaskTotal)
            } else {
                vmTaskRatio = blockRatio
            }

            let blended = 0.55 * blockRatio + 0.45 * vmTaskRatio
            let caption: String
            if viewModel.isFormulaRunStopped {
                caption = "Finished day · blocks & tasks"
            } else if viewModel.isFormulaSchedulePaused {
                caption = "Paused · \(viewModel.remainingBlockCount) blocks left"
            } else {
                caption = "\(viewModel.completedBlockCount)/\(denom) blocks · tasks"
            }
            return (min(max(blended, 0), 1), caption, true)
        }

        if viewModel.dayEngineMode == .formulaBased {
            let caption = viewModel.hasFormulaTemplate
                ? "Start the schedule to track adherence"
                : "Build a schedule on Blocks"
            return (0, caption, false)
        }

        if taskTotal == 0 {
            return (0, "Add tasks to Today to track", false)
        }
        return (taskRatio, "\(taskDone)/\(taskTotal) today’s tasks", false)
    }

    private static func awakeRing(
        calendar: Calendar,
        now: Date,
        wakeMinutes: Int,
        sleepMinutes: Int
    ) -> (progress: Double, caption: String) {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let window = max(sleepMinutes - wakeMinutes, 30)

        if nowMinutes >= sleepMinutes {
            return (1, "Past your target sleep time")
        }

        if nowMinutes < wakeMinutes {
            let leftToday = sleepMinutes - nowMinutes
            let h = leftToday / 60
            let m = leftToday % 60
            let timeStr = formatHM(hours: h, minutes: m)
            return (0, "\(timeStr) until sleep · day starts \(formatClock(minutes: wakeMinutes))")
        }

        let elapsed = nowMinutes - wakeMinutes
        let progress = min(max(Double(elapsed) / Double(window), 0), 1)
        let leftMins = sleepMinutes - nowMinutes
        let lh = leftMins / 60
        let lm = leftMins % 60
        let leftStr = formatHM(hours: lh, minutes: lm)
        return (progress, "\(leftStr) left until sleep")
    }

    private static func formatHM(hours: Int, minutes: Int) -> String {
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    private static func formatClock(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        var hour12 = h % 12
        if hour12 == 0 { hour12 = 12 }
        let am = h < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, m, am)
    }
}
