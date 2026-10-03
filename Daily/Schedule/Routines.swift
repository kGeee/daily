import SwiftUI

// MARK: - Timetables

/// A list of departure times you can pick "the next one" from: Caltrain lines,
/// the Sunnyvale station shuttle, or anything you add.
struct Timetable: Codable, Identifiable, Hashable {
    enum Live: String, Codable, CaseIterable {
        case none, homeToWork, sunnyvaleToHome, mountainViewToHome
        var title: String {
            switch self {
            case .none: return "No live data"
            case .homeToWork: return "Caltrain: your station → work"
            case .sunnyvaleToHome: return "Caltrain: Sunnyvale → home"
            case .mountainViewToHome: return "Caltrain: Mountain View → home"
            }
        }
    }

    var id: String
    var name: String
    var live: Live = .none

    static let toWork = "toWork"
    static let fromSunnyvale = "fromSunnyvale"
    static let fromMountainView = "fromMountainView"
    static let sunnyvaleShuttle = "svShuttle"

    static let defaults: [Timetable] = [
        Timetable(id: toWork, name: "Caltrain to Sunnyvale", live: .homeToWork),
        Timetable(id: fromSunnyvale, name: "Caltrain Sunnyvale → home", live: .sunnyvaleToHome),
        Timetable(id: fromMountainView, name: "Caltrain Mountain View → home", live: .mountainViewToHome),
        Timetable(id: sunnyvaleShuttle, name: "Sunnyvale station shuttle")
    ]
}

enum Timetables {
    private static let listKey = "pref.timetableList"

    /// The two original Caltrain lists keep their old storage so saved trains carry over.
    static func timesKey(_ id: String) -> String {
        switch id {
        case Timetable.toWork: return Pref.morningTrains
        case Timetable.fromSunnyvale: return Pref.eveningTrains
        default: return "pref.timetable." + id
        }
    }

    static var all: [Timetable] {
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let list = try? JSONDecoder().decode([Timetable].self, from: data), !list.isEmpty else {
            return Timetable.defaults
        }
        return list
    }

    static func save(_ list: [Timetable]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
    }

    static func get(_ id: String) -> Timetable? { all.first { $0.id == id } }

    static func times(_ id: String) -> [Int] {
        Pref.parseTrains(UserDefaults.standard.string(forKey: timesKey(id)) ?? "")
    }

    static func setTimes(_ id: String, _ minutes: [Int]) {
        UserDefaults.standard.set(Pref.joinTrains(minutes), forKey: timesKey(id))
    }

    static func name(_ id: String) -> String { get(id)?.name ?? "Timetable" }
}

// MARK: - Routine steps

enum StepKind: String, Codable, CaseIterable, Identifiable {
    case walk, shuttle, vta, caltrain, work, gym, hangout, other, drive, bus, bike
    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk / leave"
        case .shuttle: return "Shuttle"
        case .vta: return "VTA / light rail"
        case .caltrain: return "Train"
        case .work: return "Work"
        case .gym: return "Gym"
        case .hangout: return "Hang out"
        case .other: return "Other"
        case .drive: return "Drive"
        case .bus: return "Bus"
        case .bike: return "Bike"
        }
    }

    var symbol: String {
        switch self {
        case .walk: return "figure.walk"
        case .shuttle: return "bus.fill"
        case .vta: return "lightrail.fill"
        case .caltrain: return "tram.fill"
        case .work: return "briefcase.fill"
        case .gym: return "dumbbell.fill"
        case .hangout: return "cup.and.saucer.fill"
        case .other: return "star.fill"
        case .drive: return "car.fill"
        case .bus: return "bus.doubledecker.fill"
        case .bike: return "bicycle"
        }
    }

    var category: BlockCategory {
        switch self {
        case .walk, .shuttle, .vta, .caltrain, .drive, .bus, .bike: return .commute
        case .work: return .work
        case .gym: return .gym
        case .hangout, .other: return .general
        }
    }

    /// Transit steps count as departures by default (leave-by countdown, reminders).
    var isTransit: Bool { [.walk, .shuttle, .vta, .caltrain, .drive, .bus, .bike].contains(self) }
}

enum StepTiming: String, Codable, CaseIterable, Identifiable {
    /// At a set time.
    case fixed
    /// Right after the previous step ends (plus a gap).
    case afterPrevious
    /// The first departure in a timetable at or after a time (or after the previous step).
    case firstAfter
    /// The last departure in a timetable at or before a deadline.
    case lastBefore
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "At a set time"
        case .afterPrevious: return "Right after the previous step"
        case .firstAfter: return "Next departure after…"
        case .lastBefore: return "Last departure before…"
        }
    }
}

struct RoutineStep: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var kind: StepKind
    var timing: StepTiming = .fixed
    /// Minutes after midnight: the set time, the "ready at" time (firstAfter), or the deadline (lastBefore).
    var time: Int = 8 * 60
    /// For firstAfter: ignore `time` and use the end of the previous step instead.
    var readyAfterPrevious: Bool = false
    /// Gap after the previous step, for afterPrevious.
    var gap: Int = 0
    var timetableID: String? = nil
    /// How long it takes (ride time, workout length). 0 = just a moment.
    var duration: Int = 0
    /// Or a fixed end time (e.g. work until 4:00), in minutes after midnight.
    var endTime: Int? = nil
    /// Minutes to get to the stop/station before it leaves (sets "leave by").
    var walkMinutes: Int = 0
    var isDeparture: Bool = true
    var note: String = ""

    var usesTimetable: Bool { timing == .firstAfter || timing == .lastBefore }
}

/// A one-day change to a step: a different time, or skipping it.
struct StepOverride: Codable, Hashable {
    var time: Int? = nil
    var skipped: Bool = false
}

// MARK: - Routines store

enum Routines {
    private static let key = "pref.routines"
    private static let overridesKey = "pref.stepOverrides"

    private static func saved() -> [String: [RoutineStep]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: [RoutineStep]].self, from: data) else { return [:] }
        return map
    }

    static func steps(for type: DayType) -> [RoutineStep] {
        saved()[type.rawValue] ?? defaults(for: type)
    }

    static func isCustomized(_ type: DayType) -> Bool { saved()[type.rawValue] != nil }

    static func save(_ steps: [RoutineStep], for type: DayType) {
        var map = saved()
        map[type.rawValue] = steps
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func reset(_ type: DayType) {
        var map = saved()
        map[type.rawValue] = nil
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: key) }
    }

    // MARK: One-day overrides

    private static func allOverrides() -> [String: [String: StepOverride]] {
        guard let data = UserDefaults.standard.data(forKey: overridesKey),
              let map = try? JSONDecoder().decode([String: [String: StepOverride]].self, from: data) else { return [:] }
        return map
    }

    static func overrides(for dayKey: String) -> [String: StepOverride] { allOverrides()[dayKey] ?? [:] }

    static func setOverride(_ override: StepOverride?, step id: String, dayKey: String) {
        var map = allOverrides()
        var day = map[dayKey] ?? [:]
        day[id] = override
        map[dayKey] = day.isEmpty ? nil : day
        // Keep only the last few weeks.
        let cutoff = DayKey.of(Date().addingTimeInterval(-30 * 86400))
        map = map.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: overridesKey) }
    }

    // MARK: Defaults (built from your settings so older setups carry over)

    static func defaults(for type: DayType) -> [RoutineStep] {
        let shuttleOut = RoutineStep(id: "out", title: "Shuttle to work", kind: .shuttle, timing: .fixed,
                                     time: MySchedule.shuttleOut.totalMinutes, duration: 30,
                                     walkMinutes: MySchedule.walkToStopMinutes, note: MySchedule.shuttleStop)
        switch type.rawValue {
        case "shuttle":
            return [
                shuttleOut,
                RoutineStep(id: "work", title: "Work", kind: .work, timing: .fixed,
                            time: MySchedule.workStart.totalMinutes, endTime: MySchedule.shuttleHome.totalMinutes,
                            isDeparture: false),
                RoutineStep(id: "home", title: "Shuttle home", kind: .shuttle, timing: .fixed,
                            time: MySchedule.shuttleHome.totalMinutes, duration: 30, note: "From the work stop")
            ]
        case "gym":
            let gymEnd = MySchedule.gymEnd.totalMinutes
            return [
                shuttleOut,
                RoutineStep(id: "work", title: "Work", kind: .work, timing: .fixed,
                            time: MySchedule.workStart.totalMinutes, endTime: MySchedule.leaveForGym.totalMinutes,
                            isDeparture: false),
                RoutineStep(id: "go", title: "Leave for gym", kind: .walk, timing: .fixed,
                            time: MySchedule.leaveForGym.totalMinutes,
                            note: "Skip the " + MySchedule.shuttleHome.label + " shuttle today"),
                RoutineStep(id: "gym", title: "Gym", kind: .gym, timing: .fixed,
                            time: MySchedule.gymStart.totalMinutes, endTime: gymEnd, isDeparture: false),
                RoutineStep(id: "home", title: "Caltrain home", kind: .caltrain, timing: .firstAfter,
                            time: gymEnd + MySchedule.gymToStationMinutes, timetableID: Timetable.fromSunnyvale,
                            duration: MySchedule.caltrainRideMinutes, walkMinutes: MySchedule.gymToStationMinutes,
                            note: "From Sunnyvale")
            ]
        case "caltrain":
            let mustLeaveBy = MySchedule.workStart.totalMinutes - MySchedule.caltrainRideMinutes - MySchedule.lastMileMinutes
            return [
                RoutineStep(id: "out", title: "Caltrain to Sunnyvale", kind: .caltrain, timing: .lastBefore,
                            time: mustLeaveBy, timetableID: Timetable.toWork, duration: MySchedule.caltrainRideMinutes,
                            walkMinutes: MySchedule.walkToStationMinutes, note: MySchedule.homeStation),
                RoutineStep(id: "vta-in", title: "VTA to the office", kind: .vta, timing: .afterPrevious,
                            gap: 3, duration: max(MySchedule.lastMileMinutes - 3, 5),
                            note: "Or the Sunnyvale station shuttle"),
                RoutineStep(id: "work", title: "Work", kind: .work, timing: .fixed,
                            time: MySchedule.workStart.totalMinutes, endTime: MySchedule.caltrainLeaveWork.totalMinutes,
                            isDeparture: false),
                RoutineStep(id: "vta-out", title: "VTA to Sunnyvale station", kind: .vta, timing: .fixed,
                            time: MySchedule.caltrainLeaveWork.totalMinutes, duration: MySchedule.lastMileMinutes),
                RoutineStep(id: "home", title: "Caltrain home", kind: .caltrain, timing: .firstAfter,
                            readyAfterPrevious: true, timetableID: Timetable.fromSunnyvale,
                            duration: MySchedule.caltrainRideMinutes, note: "From Sunnyvale")
            ]
        case "mountainView":
            return [
                shuttleOut,
                RoutineStep(id: "work", title: "Work", kind: .work, timing: .fixed,
                            time: MySchedule.workStart.totalMinutes, endTime: MySchedule.shuttleHome.totalMinutes,
                            isDeparture: false),
                RoutineStep(id: "vta-mv", title: "VTA to Mountain View", kind: .vta, timing: .fixed,
                            time: MySchedule.shuttleHome.totalMinutes, duration: 25),
                RoutineStep(id: "hangout", title: "Hang out in Mountain View", kind: .hangout, timing: .afterPrevious,
                            duration: 120, isDeparture: false, note: "Castro St"),
                RoutineStep(id: "home", title: "Caltrain home", kind: .caltrain, timing: .firstAfter,
                            readyAfterPrevious: true, timetableID: Timetable.fromMountainView,
                            duration: MySchedule.caltrainRideMinutes, walkMinutes: 5, note: "From Mountain View")
            ]
        default:
            // A kind of day you made yourself starts empty until you add steps.
            return []
        }
    }
}

// MARK: - Turning a routine into timeline blocks

enum RoutineResolver {
    struct Resolved {
        let step: RoutineStep
        let start: Int          // minutes after midnight
        let end: Int?
        let isEstimate: Bool
        let nextAlternative: Int?
    }

    /// Works out each step's time for one day, in order. Steps chain: "after previous" and
    /// "next departure after previous" use where the previous step ends.
    static func resolve(_ steps: [RoutineStep], overrides: [String: StepOverride] = [:],
                        timesFor: (String) -> [Int] = Timetables.times) -> [Resolved] {
        var result: [Resolved] = []
        var previousEnd: Int? = nil

        for step in steps {
            let override = overrides[step.id]
            if override?.skipped == true { continue }

            var start: Int
            var estimate = false
            var alternative: Int? = nil

            if let fixed = override?.time {
                start = fixed
            } else {
                switch step.timing {
                case .fixed:
                    start = step.time
                case .afterPrevious:
                    start = (previousEnd ?? step.time) + step.gap
                case .firstAfter:
                    let ready = step.readyAfterPrevious ? (previousEnd ?? step.time) + step.walkMinutes : step.time
                    let times = step.timetableID.map(timesFor) ?? []
                    if let pick = times.first(where: { $0 >= ready }) {
                        start = pick
                        alternative = times.first { $0 > pick }
                    } else {
                        start = ready + 10
                        estimate = true
                    }
                case .lastBefore:
                    let times = step.timetableID.map(timesFor) ?? []
                    if let pick = times.last(where: { $0 <= step.time }) ?? times.first {
                        start = pick
                        alternative = times.last { $0 < pick }
                    } else {
                        start = step.time
                        estimate = true
                    }
                }
            }

            let end: Int?
            if let endTime = step.endTime {
                end = max(endTime, start)
            } else if step.duration > 0 {
                end = start + step.duration
            } else {
                end = nil
            }
            previousEnd = end ?? start
            result.append(Resolved(step: step, start: start, end: end, isEstimate: estimate, nextAlternative: alternative))
        }
        return result
    }

    static func blocks(for day: Date, type: DayType, gymNote: String?) -> [TimelineBlock] {
        let d = Calendar.current.startOfDay(for: day)
        let resolved = resolve(Routines.steps(for: type), overrides: Routines.overrides(for: DayKey.of(d)))
        return resolved.map { r in
            let step = r.step
            let start = ClockTime(minutes: r.start).on(d)
            let leaveBy = step.walkMinutes > 0 ? start.addingTimeInterval(-Double(step.walkMinutes * 60)) : start
            var parts: [String] = []
            if step.kind == .gym, let gymNote, !gymNote.isEmpty { parts.append(gymNote) }
            if !step.note.isEmpty { parts.append(step.note) }
            if step.isDeparture && step.walkMinutes > 0 {
                parts.append("leave by " + leaveBy.formatted(date: .omitted, time: .shortened))
            }
            if let alt = r.nextAlternative, step.timing == .firstAfter {
                parts.append("next one " + ClockTime(minutes: alt).label)
            }
            return TimelineBlock(
                id: step.id, start: start,
                end: r.end.map { ClockTime(minutes: $0).on(d) },
                title: step.title, subtitle: parts.joined(separator: " · "),
                category: step.kind.category, symbol: step.kind.symbol,
                isEstimate: r.isEstimate, isDeparture: step.isDeparture,
                leaveBy: step.isDeparture ? leaveBy : nil,
                routineType: type)
        }
    }
}
