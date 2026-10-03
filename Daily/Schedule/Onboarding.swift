import Foundation

/// Ways of getting to work you can pick during setup. Each one you pick becomes a kind of day.
enum CommuteMode: String, Codable, CaseIterable, Identifiable {
    case drive, shuttle, train, bus, bike, remote
    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: return "Drive"
        case .shuttle: return "Work shuttle"
        case .train: return "Train"
        case .bus: return "Bus or light rail"
        case .bike: return "Bike or walk"
        case .remote: return "Work from home"
        }
    }

    var blurb: String {
        switch self {
        case .drive: return "Your own car"
        case .shuttle: return "A company shuttle at set times"
        case .train: return "Caltrain, BART, any line"
        case .bus: return "VTA, Muni, any route"
        case .bike: return "Door to door"
        case .remote: return "No commute"
        }
    }

    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .shuttle: return "bus.fill"
        case .train: return "tram.fill"
        case .bus: return "bus.doubledecker.fill"
        case .bike: return "bicycle"
        case .remote: return "house.fill"
        }
    }
}

/// How you get from the train to the office (and back).
enum LastMile: String, Codable, CaseIterable, Identifiable {
    case none, walk, bike, transit, shuttle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "It's right there"
        case .walk: return "Walk"
        case .bike: return "Bike"
        case .transit: return "Bus / VTA"
        case .shuttle: return "Station shuttle"
        }
    }

    var kind: StepKind {
        switch self {
        case .none, .walk: return .walk
        case .bike: return .bike
        case .transit: return .vta
        case .shuttle: return .shuttle
        }
    }
}

/// Everything asked during setup. `plan()` turns it into kinds of day, routines, timetables and a week.
struct SetupAnswers: Equatable {
    // Your day
    var wake = 6 * 60 + 45
    var workStart = 9 * 60
    var workEnd = 17 * 60
    var bedtime = 23 * 60

    // How you commute (in the order picked)
    var modes: [CommuteMode] = []

    // Driving
    var driveMinutes = 30
    var parkMinutes = 5

    // Work shuttle
    var shuttleOut = 7 * 60 + 45
    var shuttleHome = 16 * 60
    var shuttleRide = 35
    var shuttleStop = ""
    var walkToStop = 10

    // Train
    var trainLine = "Caltrain"
    var fromStation = ""
    var toStation = ""
    var trainRide = 30
    var walkToStation = 10
    var lastMile: LastMile = .walk
    var lastMileMinutes = 10

    // Bus / light rail
    var busLine = "Bus"
    var busRide = 30
    var walkToBus = 5

    // Bike / walk
    var bikeMinutes = 25

    // Gym after work
    var gym = false
    var gymMode: CommuteMode = .drive
    var gymHome: CommuteMode = .drive
    var gymLeave = 16 * 60 + 30
    var gymTravel = 15
    var workoutLength = 75

    // A regular after-work spot (e.g. hanging out in Mountain View)
    var outing = false
    var outingPlace = ""
    var outingMode: CommuteMode = .drive
    var outingHome: CommuteMode = .drive
    var outingTravel = 20
    var outingLength = 120

    /// Mon…Sun: a kind-of-day id, or "off".
    var week: [String] = Array(repeating: DayPlanner.off, count: 7)

    var outingName: String {
        let trimmed = outingPlace.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "After-work plans" : trimmed
    }

    /// Every kind of day these answers make, in order.
    var dayTypeIDs: [String] {
        var ids = modes.map(\.rawValue)
        if gym { ids.append("gym") }
        if outing { ids.append("outing") }
        return ids
    }

    /// Fill in a sensible week once modes are picked: weekdays on the first mode, weekends off.
    mutating func suggestWeek() {
        let valid = Set(dayTypeIDs)
        let first = modes.first?.rawValue ?? DayPlanner.off
        for i in 0..<7 where !valid.contains(week[i]) {
            week[i] = i < 5 ? first : DayPlanner.off
        }
    }
}

struct SetupPlan {
    var dayTypes: [DayTypeInfo]
    var routines: [String: [RoutineStep]]
    var timetables: [Timetable]
    var pattern: String
}

enum Setup {
    static let doneKey = "pref.onboarded"

    static let trainOut = "train-out"
    static let trainHome = "train-home"
    static let outingHome = "outing-home"

    // MARK: Building the plan

    static func plan(_ a: SetupAnswers) -> SetupPlan {
        var types: [DayTypeInfo] = []
        var routines: [String: [RoutineStep]] = [:]

        for mode in a.modes {
            types.append(info(for: mode, a))
            routines[mode.rawValue] = outbound(mode, a) + [work(a, until: a.workEnd)] + inbound(mode, a)
        }

        if a.gym {
            types.append(DayTypeInfo(id: "gym", name: "Gym day", short: "Gym", color: .gym))
            let toGymKind: StepKind = a.gymMode == .drive ? .drive : (a.gymMode == .bike ? .bike : .walk)
            var steps = outbound(a.gymMode, a)
            steps.append(work(a, until: a.gymLeave))
            steps.append(RoutineStep(id: "go", title: "Head to the gym", kind: toGymKind, timing: .fixed,
                                     time: a.gymLeave, duration: a.gymTravel))
            steps.append(RoutineStep(id: "gym", title: "Gym", kind: .gym, timing: .afterPrevious,
                                     time: a.gymLeave + a.gymTravel, duration: a.workoutLength, isDeparture: false))
            steps.append(homeLeg(a.gymHome, from: "the gym", timetable: trainHome, travel: a.gymTravel, a))
            routines["gym"] = steps
        }

        if a.outing {
            let name = a.outingName
            types.append(DayTypeInfo(id: "outing", name: name + " day", short: String(name.prefix(10)), color: .general))
            var steps = outbound(a.outingMode, a)
            steps.append(work(a, until: a.workEnd))
            steps.append(RoutineStep(id: "go-out", title: "Head to " + name, kind: kind(forTrip: a.outingMode), timing: .fixed,
                                     time: a.workEnd, duration: a.outingTravel))
            steps.append(RoutineStep(id: "hangout", title: name, kind: .hangout, timing: .afterPrevious,
                                     duration: a.outingLength, isDeparture: false))
            steps.append(homeLeg(a.outingHome, from: name, timetable: outingHome, travel: a.outingTravel, a))
            routines["outing"] = steps
        }

        var pattern = a.week
        let valid = Set(types.map(\.id))
        for i in pattern.indices where !valid.contains(pattern[i]) { pattern[i] = DayPlanner.off }

        return SetupPlan(dayTypes: types, routines: routines, timetables: timetables(a), pattern: pattern.joined(separator: ","))
    }

    private static func info(for mode: CommuteMode, _ a: SetupAnswers) -> DayTypeInfo {
        switch mode {
        case .drive: return DayTypeInfo(id: mode.rawValue, name: "Driving day", short: "Drive", color: .water)
        case .shuttle: return DayTypeInfo(id: mode.rawValue, name: "Shuttle day", short: "Shuttle", color: .commute)
        case .train:
            let line = clean(a.trainLine, "Train")
            return DayTypeInfo(id: mode.rawValue, name: line + " day", short: String(line.prefix(10)), color: .caltrain)
        case .bus:
            let line = clean(a.busLine, "Bus")
            return DayTypeInfo(id: mode.rawValue, name: line + " day", short: String(line.prefix(10)), color: .sleep)
        case .bike: return DayTypeInfo(id: mode.rawValue, name: "Bike day", short: "Bike", color: .food)
        case .remote: return DayTypeInfo(id: mode.rawValue, name: "Home day", short: "Home", color: .focus)
        }
    }

    private static func clean(_ text: String, _ fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func kind(forTrip mode: CommuteMode) -> StepKind {
        switch mode {
        case .drive: return .drive
        case .bike: return .bike
        case .bus: return .bus
        case .train: return .vta
        default: return .walk
        }
    }

    private static func work(_ a: SetupAnswers, until end: Int) -> RoutineStep {
        RoutineStep(id: "work", title: "Work", kind: .work, timing: .fixed,
                    time: a.workStart, endTime: max(end, a.workStart), isDeparture: false)
    }

    /// Getting to work so you arrive by the start time.
    static func outbound(_ mode: CommuteMode, _ a: SetupAnswers) -> [RoutineStep] {
        switch mode {
        case .drive:
            return [RoutineStep(id: "out", title: "Drive to work", kind: .drive, timing: .fixed,
                                time: a.workStart - a.driveMinutes - a.parkMinutes, duration: a.driveMinutes,
                                note: a.parkMinutes > 0 ? "\(a.parkMinutes) min to park" : "")]
        case .shuttle:
            return [RoutineStep(id: "out", title: "Shuttle to work", kind: .shuttle, timing: .fixed,
                                time: a.shuttleOut, duration: a.shuttleRide, walkMinutes: a.walkToStop,
                                note: clean(a.shuttleStop, ""))]
        case .train:
            let line = clean(a.trainLine, "Train")
            let lastMile = a.lastMile == .none ? 0 : a.lastMileMinutes
            var steps = [RoutineStep(id: "out", title: line + " to " + clean(a.toStation, "work"), kind: .caltrain,
                                     timing: .lastBefore, time: a.workStart - a.trainRide - lastMile,
                                     timetableID: trainOut, duration: a.trainRide, walkMinutes: a.walkToStation,
                                     note: clean(a.fromStation, ""))]
            if lastMile > 0 {
                steps.append(RoutineStep(id: "last-in", title: a.lastMile.title + " to the office", kind: a.lastMile.kind,
                                         timing: .afterPrevious, duration: lastMile, isDeparture: false))
            }
            return steps
        case .bus:
            return [RoutineStep(id: "out", title: clean(a.busLine, "Bus") + " to work", kind: .bus, timing: .fixed,
                                time: a.workStart - a.busRide, duration: a.busRide, walkMinutes: a.walkToBus)]
        case .bike:
            return [RoutineStep(id: "out", title: "Bike to work", kind: .bike, timing: .fixed,
                                time: a.workStart - a.bikeMinutes, duration: a.bikeMinutes)]
        case .remote:
            return []
        }
    }

    /// Getting home from work at the end of the day.
    static func inbound(_ mode: CommuteMode, _ a: SetupAnswers) -> [RoutineStep] {
        switch mode {
        case .drive:
            return [RoutineStep(id: "home", title: "Drive home", kind: .drive, timing: .fixed,
                                time: a.workEnd, duration: a.driveMinutes)]
        case .shuttle:
            return [RoutineStep(id: "home", title: "Shuttle home", kind: .shuttle, timing: .fixed,
                                time: a.shuttleHome, duration: a.shuttleRide)]
        case .train:
            let line = clean(a.trainLine, "Train")
            let lastMile = a.lastMile == .none ? 0 : a.lastMileMinutes
            var steps: [RoutineStep] = []
            if lastMile > 0 {
                steps.append(RoutineStep(id: "last-out", title: a.lastMile.title + " to " + clean(a.toStation, "the station"),
                                         kind: a.lastMile.kind, timing: .fixed, time: a.workEnd, duration: lastMile))
            }
            steps.append(RoutineStep(id: "home", title: line + " home", kind: .caltrain, timing: .firstAfter,
                                     time: a.workEnd + (lastMile > 0 ? lastMile : a.walkToStation),
                                     readyAfterPrevious: lastMile > 0, timetableID: trainHome,
                                     duration: a.trainRide, walkMinutes: lastMile > 0 ? 0 : a.walkToStation,
                                     note: a.toStation.isEmpty ? "" : "From " + a.toStation))
            return steps
        case .bus:
            return [RoutineStep(id: "home", title: clean(a.busLine, "Bus") + " home", kind: .bus, timing: .fixed,
                                time: a.workEnd, duration: a.busRide, walkMinutes: a.walkToBus)]
        case .bike:
            return [RoutineStep(id: "home", title: "Bike home", kind: .bike, timing: .fixed,
                                time: a.workEnd, duration: a.bikeMinutes)]
        case .remote:
            return []
        }
    }

    /// Getting home after the gym or an outing (follows on from the previous step).
    static func homeLeg(_ mode: CommuteMode, from place: String, timetable: String, travel: Int,
                        _ a: SetupAnswers) -> RoutineStep {
        switch mode {
        case .train:
            return RoutineStep(id: "home", title: clean(a.trainLine, "Train") + " home", kind: .caltrain,
                               timing: .firstAfter, readyAfterPrevious: true, timetableID: timetable,
                               duration: a.trainRide, walkMinutes: 10, note: "From " + place)
        case .drive:
            return RoutineStep(id: "home", title: "Drive home", kind: .drive, timing: .afterPrevious,
                               duration: a.driveMinutes)
        case .bus:
            return RoutineStep(id: "home", title: clean(a.busLine, "Bus") + " home", kind: .bus, timing: .afterPrevious,
                               gap: a.walkToBus, duration: a.busRide)
        case .bike:
            return RoutineStep(id: "home", title: "Bike home", kind: .bike, timing: .afterPrevious,
                               duration: a.bikeMinutes)
        case .shuttle:
            return RoutineStep(id: "home", title: "Head home", kind: .walk, timing: .afterPrevious,
                               duration: a.shuttleRide)
        case .remote:
            return RoutineStep(id: "home", title: "Head home", kind: .walk, timing: .afterPrevious,
                               duration: travel)
        }
    }

    static func usesTrain(_ a: SetupAnswers) -> Bool {
        a.modes.contains(.train) || (a.gym && (a.gymMode == .train || a.gymHome == .train))
            || (a.outing && (a.outingMode == .train || a.outingHome == .train))
    }

    static func timetables(_ a: SetupAnswers) -> [Timetable] {
        guard usesTrain(a) else { return [] }
        let line = clean(a.trainLine, "Train")
        let from = clean(a.fromStation, "Home"), to = clean(a.toStation, "Work")
        let isCaltrain = line.lowercased().contains("caltrain")
        var list = [
            Timetable(id: trainOut, name: "\(line): \(from) → \(to)", live: isCaltrain ? .homeToWork : .none),
            Timetable(id: trainHome, name: "\(line): \(to) → \(from)",
                      live: isCaltrain && to.lowercased().contains("sunnyvale") ? .sunnyvaleToHome : .none)
        ]
        if a.outing && a.outingHome == .train {
            list.append(Timetable(id: outingHome, name: "\(line): \(a.outingName) → \(from)",
                                  live: isCaltrain && a.outingName.lowercased().contains("mountain view") ? .mountainViewToHome : .none))
        }
        return list
    }

    // MARK: Saving

    /// Writes the plan: kinds of day, routines, timetables, your week and basic times.
    static func apply(_ a: SetupAnswers, defaults: UserDefaults = .standard) {
        let result = Self.plan(a)
        guard !result.dayTypes.isEmpty else { return }
        DayTypes.save(result.dayTypes)
        for (id, steps) in result.routines {
            if let type = DayType(rawValue: id) { Routines.save(steps, for: type) }
        }
        // Keep timetables you've already filled in; replace the ones setup makes.
        let made = Set(result.timetables.map(\.id))
        let kept = Timetables.all.filter { !made.contains($0.id) && !Timetables.times($0.id).isEmpty }
        Timetables.save(result.timetables + kept)

        defaults.set(result.pattern, forKey: "weekPattern")
        defaults.set(a.wake, forKey: Pref.wake)
        defaults.set(a.workStart, forKey: Pref.workStart)
        defaults.set(a.bedtime, forKey: Pref.bedtime)
        defaults.set(max(a.bedtime - 30, 0), forKey: Pref.windDown)
        if a.modes.contains(.train) {
            defaults.set(a.fromStation, forKey: Pref.homeStation)
            defaults.set(a.trainRide, forKey: Pref.caltrainRide)
            defaults.set(a.walkToStation, forKey: Pref.walkToStation)
        }
        if a.modes.contains(.shuttle) {
            defaults.set(a.shuttleOut, forKey: Pref.shuttleOut)
            defaults.set(a.shuttleHome, forKey: Pref.shuttleHome)
            defaults.set(a.shuttleStop, forKey: Pref.shuttleStop)
            defaults.set(a.walkToStop, forKey: Pref.walkToStop)
        }
        defaults.set(true, forKey: doneKey)
        Pref.bump()
    }

    /// Older installs already set up by hand skip the setup screens.
    static func needsSetup(defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: doneKey) { return false }
        let alreadyUsed = defaults.integer(forKey: Pref.revision) > 0
            || defaults.object(forKey: "weekPattern") != nil
            || defaults.data(forKey: "pref.routines") != nil
        if alreadyUsed {
            defaults.set(true, forKey: doneKey)
            return false
        }
        return true
    }
}
