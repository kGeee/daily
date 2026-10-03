import SwiftUI

struct ClockTime: Hashable {
    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(minutes: Int) {
        let m = ((minutes % 1440) + 1440) % 1440
        self.init(m / 60, m % 60)
    }

    var totalMinutes: Int { hour * 60 + minute }

    func adding(_ minutes: Int) -> ClockTime { ClockTime(minutes: totalMinutes + minutes) }

    func on(_ day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var label: String {
        on(Date()).formatted(date: .omitted, time: .shortened)
    }
}

/// Storage keys and defaults for everything you can change in Settings.
/// Times are stored as minutes after midnight.
enum Pref {
    static let wake = "pref.wake",                   wakeDefault = 6 * 60 + 50
    static let workStart = "pref.workStart",         workStartDefault = 8 * 60 + 30
    static let lunch = "pref.lunch",                 lunchDefault = 12 * 60
    static let dinner = "pref.dinner",               dinnerDefault = 18 * 60 + 30
    static let windDown = "pref.windDown",           windDownDefault = 23 * 60
    static let bedtime = "pref.bedtime",             bedtimeDefault = 23 * 60 + 30

    static let shuttleOut = "pref.shuttleOut",       shuttleOutDefault = 7 * 60 + 45
    static let shuttleHome = "pref.shuttleHome",     shuttleHomeDefault = 16 * 60
    static let walkToStop = "pref.walkToStop",       walkToStopDefault = 10
    static let shuttleStop = "pref.shuttleStop",     shuttleStopDefault = "Your shuttle stop"

    static let leaveForGym = "pref.leaveForGym",     leaveForGymDefault = 15 * 60
    static let gymTravel = "pref.gymTravel",         gymTravelDefault = 30
    static let workoutLength = "pref.workoutLength", workoutLengthDefault = 85
    static let gymToStation = "pref.gymToStation",   gymToStationDefault = 20

    static let homeStation = "pref.homeStation",     homeStationDefault = "Your station"
    static let walkToStation = "pref.walkToStation", walkToStationDefault = 10
    static let caltrainRide = "pref.caltrainRide",   caltrainRideDefault = 30
    static let lastMile = "pref.lastMile",           lastMileDefault = 15
    static let caltrainLeaveWork = "pref.caltrainLeaveWork", caltrainLeaveWorkDefault = 16 * 60 + 30
    static let morningTrains = "pref.morningTrains"  // comma-separated minutes, home → Sunnyvale
    static let eveningTrains = "pref.eveningTrains"  // comma-separated minutes, Sunnyvale → home

    static let prepStart = "pref.prepStart",         prepStartDefault = 16 * 60
    static let prepEnd = "pref.prepEnd",             prepEndDefault = 18 * 60

    static let reminderLead = "pref.reminderLead",   reminderLeadDefault = 10
    static let waterGoal = "pref.waterGoal",         waterGoalDefault = 100
    static let eatOutGoal = "pref.eatOutGoal",       eatOutGoalDefault = 2
    static let calorieGoal = "pref.calorieGoal",     calorieGoalDefault = 2200
    static let proteinGoal = "pref.proteinGoal",     proteinGoalDefault = 140

    // Live Caltrain (511.org)
    static let liveStationName = "pref.liveStationName"   // e.g. "San Francisco"
    static let liveHomeStops = "pref.liveHomeStops"       // comma-separated 511 stop IDs for your station
    static let liveSunnyvaleStops = "pref.liveSunnyvaleStops"
    static let liveMountainViewStops = "pref.liveMountainViewStops"
    static let directionToWork = "pref.directionToWork",  directionToWorkDefault = "S"

    /// Bumped whenever settings change so screens redraw.
    static let revision = "pref.revision"

    static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revision) + 1, forKey: revision)
    }

    static func parseTrains(_ raw: String) -> [Int] {
        raw.split(separator: ",").compactMap { Int($0) }.sorted()
    }

    static func joinTrains(_ minutes: [Int]) -> String {
        Array(Set(minutes)).sorted().map(String.init).joined(separator: ",")
    }
}

/// Your personal schedule, read from Settings (with sensible defaults).
enum MySchedule {
    private static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    private static func string(_ key: String, _ fallback: String) -> String {
        let value = UserDefaults.standard.string(forKey: key) ?? ""
        return value.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : value
    }
    private static func time(_ key: String, _ fallback: Int) -> ClockTime {
        ClockTime(minutes: int(key, fallback))
    }

    static var wake: ClockTime { time(Pref.wake, Pref.wakeDefault) }
    static var workStart: ClockTime { time(Pref.workStart, Pref.workStartDefault) }
    static var lunch: ClockTime { time(Pref.lunch, Pref.lunchDefault) }
    static var dinner: ClockTime { time(Pref.dinner, Pref.dinnerDefault) }
    static var windDown: ClockTime { time(Pref.windDown, Pref.windDownDefault) }
    static var bedtime: ClockTime { time(Pref.bedtime, Pref.bedtimeDefault) }

    static var shuttleOut: ClockTime { time(Pref.shuttleOut, Pref.shuttleOutDefault) }
    static var shuttleHome: ClockTime { time(Pref.shuttleHome, Pref.shuttleHomeDefault) }
    static var walkToStopMinutes: Int { int(Pref.walkToStop, Pref.walkToStopDefault) }
    static var shuttleStop: String { string(Pref.shuttleStop, Pref.shuttleStopDefault) }

    static var leaveForGym: ClockTime { time(Pref.leaveForGym, Pref.leaveForGymDefault) }
    static var gymStart: ClockTime { leaveForGym.adding(int(Pref.gymTravel, Pref.gymTravelDefault)) }
    static var gymEnd: ClockTime { gymStart.adding(int(Pref.workoutLength, Pref.workoutLengthDefault)) }
    static var gymToStationMinutes: Int { int(Pref.gymToStation, Pref.gymToStationDefault) }

    static var homeStation: String { string(Pref.homeStation, Pref.homeStationDefault) }
    static var walkToStationMinutes: Int { int(Pref.walkToStation, Pref.walkToStationDefault) }
    static var caltrainRideMinutes: Int { int(Pref.caltrainRide, Pref.caltrainRideDefault) }
    static var lastMileMinutes: Int { int(Pref.lastMile, Pref.lastMileDefault) }
    static var caltrainLeaveWork: ClockTime { time(Pref.caltrainLeaveWork, Pref.caltrainLeaveWorkDefault) }
    static var morningTrains: [Int] { Pref.parseTrains(UserDefaults.standard.string(forKey: Pref.morningTrains) ?? "") }
    static var eveningTrains: [Int] { Pref.parseTrains(UserDefaults.standard.string(forKey: Pref.eveningTrains) ?? "") }

    static var prepStart: ClockTime { time(Pref.prepStart, Pref.prepStartDefault) }
    static var prepEnd: ClockTime { time(Pref.prepEnd, Pref.prepEndDefault) }

    static var reminderLeadMinutes: Int { int(Pref.reminderLead, Pref.reminderLeadDefault) }
    static var waterGoalOz: Int { int(Pref.waterGoal, Pref.waterGoalDefault) }
    static var eatOutGoalPerWeek: Int { int(Pref.eatOutGoal, Pref.eatOutGoalDefault) }
    static var calorieGoal: Int { int(Pref.calorieGoal, Pref.calorieGoalDefault) }
    static var proteinGoal: Int { int(Pref.proteinGoal, Pref.proteinGoalDefault) }

    /// Usual day type for Mon–Fri, in order.
    static let defaultPattern = "shuttle,gym,gym,shuttle,caltrain"

    // MARK: Caltrain

    /// Latest morning train that still gets you to work on time.
    /// Falls back to an estimate when you haven't added your trains yet.
    static var caltrainOut: (time: ClockTime, isEstimate: Bool) {
        let mustLeaveBy = workStart.totalMinutes - caltrainRideMinutes - lastMileMinutes
        let trains = morningTrains
        if let pick = trains.last(where: { $0 <= mustLeaveBy }) ?? trains.first {
            return (ClockTime(minutes: pick), false)
        }
        return (ClockTime(minutes: mustLeaveBy), true)
    }

    /// First evening train you can make after you're ready to leave.
    static func caltrainHome(readyAt ready: ClockTime) -> (time: ClockTime, isEstimate: Bool) {
        let trains = eveningTrains
        if let pick = trains.first(where: { $0 >= ready.totalMinutes }) {
            return (ClockTime(minutes: pick), false)
        }
        return (ready.adding(10), true)
    }

    static var caltrainAfterGym: (time: ClockTime, isEstimate: Bool) {
        caltrainHome(readyAt: gymEnd.adding(gymToStationMinutes))
    }

    static var caltrainAfterWork: (time: ClockTime, isEstimate: Bool) {
        caltrainHome(readyAt: caltrainLeaveWork.adding(lastMileMinutes))
    }

    /// Evening trains after the given one, for showing backups.
    static func trains(after minutes: Int, count: Int) -> [ClockTime] {
        eveningTrains.filter { $0 > minutes }.prefix(count).map { ClockTime(minutes: $0) }
    }
}

/// Colors a kind of day can use (all from Palette).
enum DayColor: String, Codable, CaseIterable {
    case commute, gym, caltrain, general, food, water, sleep, focus

    var color: Color {
        switch self {
        case .commute: return Palette.commute
        case .gym: return Palette.gym
        case .caltrain: return Palette.caltrain
        case .general: return Palette.general
        case .food: return Palette.food
        case .water: return Palette.water
        case .sleep: return Palette.sleep
        case .focus: return Palette.focus
        }
    }

    var tint: Color {
        switch self {
        case .commute: return Palette.commuteTint
        case .gym: return Palette.gymTint
        case .caltrain: return Palette.caltrainTint
        case .general: return Palette.generalTint
        case .food: return Palette.foodTint
        case .water: return Palette.waterTint
        case .sleep: return Palette.circle
        case .focus: return Palette.focusTint
        }
    }
}

/// How a kind of day is shown: "Driving day" / "Drive", in a color.
struct DayTypeInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var short: String
    var color: DayColor
}

/// The kinds of day you have set up. Until you run setup, these are the original four.
enum DayTypes {
    static let key = "pref.dayTypes"

    static let builtIns: [DayTypeInfo] = [
        DayTypeInfo(id: "shuttle", name: "Shuttle day", short: "Shuttle", color: .commute),
        DayTypeInfo(id: "gym", name: "Gym day", short: "Gym", color: .gym),
        DayTypeInfo(id: "caltrain", name: "Caltrain day", short: "Caltrain", color: .caltrain),
        DayTypeInfo(id: "mountainView", name: "Mountain View day", short: "Mtn View", color: .general)
    ]

    nonisolated(unsafe) private static var cache: (data: Data?, list: [DayTypeInfo])? = nil

    static var all: [DayTypeInfo] {
        let data = UserDefaults.standard.data(forKey: key)
        if let cache, cache.data == data { return cache.list }
        let list: [DayTypeInfo]
        if let data, let saved = try? JSONDecoder().decode([DayTypeInfo].self, from: data) {
            list = saved
        } else {
            list = builtIns
        }
        cache = (data, list)
        return list
    }

    static func save(_ list: [DayTypeInfo]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func info(_ id: String) -> DayTypeInfo? { all.first { $0.id == id } }
}

/// A kind of day (shuttle day, driving day, gym day…). Which ones exist is up to you (see `DayTypes`).
struct DayType: Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    /// Only kinds of day you have set up.
    init?(rawValue: String) {
        guard DayTypes.info(rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    fileprivate init(id: String) {
        self.rawValue = id
    }

    static let shuttle = DayType(id: "shuttle")
    static let gym = DayType(id: "gym")
    static let caltrain = DayType(id: "caltrain")
    static let mountainView = DayType(id: "mountainView")

    static var allCases: [DayType] { DayTypes.all.map { DayType(id: $0.id) } }

    private var info: DayTypeInfo {
        DayTypes.info(rawValue)
            ?? DayTypes.builtIns.first { $0.id == rawValue }
            ?? DayTypeInfo(id: rawValue, name: rawValue.capitalized + " day", short: rawValue.capitalized, color: .general)
    }

    var title: String { info.name }
    var short: String { info.short }
    var color: Color { info.color.color }
    var tint: Color { info.color.tint }
}

enum BlockCategory {
    case sleep, commute, work, food, gym, general

    var color: Color {
        switch self {
        case .general: return Palette.general
        case .sleep: return Palette.sleep
        case .commute: return Palette.commute
        case .work: return Palette.work
        case .food: return Palette.food
        case .gym: return Palette.gym
        }
    }
}

struct TimelineBlock: Identifiable {
    let id: String
    let start: Date
    var end: Date? = nil
    let title: String
    var subtitle: String = ""
    let category: BlockCategory
    let symbol: String
    var isEstimate: Bool = false
    var isDeparture: Bool = false
    var eventID: UUID? = nil
    /// When you need to walk out the door (before the departure itself).
    var leaveBy: Date? = nil
    /// Set for blocks that come from a commute routine (so they can be edited).
    var routineType: DayType? = nil
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
}

/// Works out what kind of day it is and builds the timeline for it.
struct DayPlanner {
    var pattern: String
    var overrides: [DayTypeOverride]

    /// The pattern lists Mon…Fri, then optionally Sat and Sun. "off" (or anything unknown) = no commute.
    static func patternIndex(forWeekday weekday: Int) -> Int {
        weekday == 1 ? 6 : weekday - 2   // weekday: 1 = Sunday … 7 = Saturday
    }

    func usualType(forWeekday weekday: Int) -> DayType? {
        let parts = pattern.split(separator: ",").map(String.init)
        let index = Self.patternIndex(forWeekday: weekday)
        guard index >= 0, index < parts.count else { return nil }
        return DayType(rawValue: parts[index])
    }

    func type(for date: Date) -> DayType? {
        let key = DayKey.of(date)
        if let override = overrides.first(where: { $0.dayKey == key }) {
            return DayType(rawValue: override.typeRaw)   // "off" = a day off
        }
        return usualType(forWeekday: Calendar.current.component(.weekday, from: date))
    }

    static func updating(pattern: String, weekday: Int, to type: DayType?) -> String {
        var parts = pattern.split(separator: ",").map(String.init)
        let index = patternIndex(forWeekday: weekday)
        while parts.count < max(5, index + 1) { parts.append(parts.count < 5 ? DayType.shuttle.rawValue : DayPlanner.off) }
        parts[index] = type?.rawValue ?? DayPlanner.off
        return parts.joined(separator: ",")
    }

    static let off = "off"

    func blocks(for day: Date, lunchNote: String?, dinnerNote: String?,
                gymNote: String? = nil, events: [CustomEvent] = []) -> [TimelineBlock] {
        let d = Calendar.current.startOfDay(for: day)
        let weekday = Calendar.current.component(.weekday, from: d)

        var out: [TimelineBlock] = [
            TimelineBlock(id: "wake", start: MySchedule.wake.on(d), title: "Rise and shine", category: .sleep, symbol: "alarm.fill")
        ]
        let lunch = TimelineBlock(id: "lunch", start: MySchedule.lunch.on(d), title: "Lunch",
                                  subtitle: lunchNote ?? "Nothing planned", category: .food, symbol: "fork.knife")
        let dinner = TimelineBlock(id: "dinner", start: MySchedule.dinner.on(d), title: "Dinner",
                                   subtitle: dinnerNote ?? "Nothing planned", category: .food, symbol: "fork.knife")

        if let dayType = type(for: d) {
            out += RoutineResolver.blocks(for: d, type: dayType, gymNote: gymNote)
            out.append(lunch)
        } else {
            out.append(lunch)
            if weekday == 1 {
                out.append(TimelineBlock(id: "prep", start: MySchedule.prepStart.on(d), end: MySchedule.prepEnd.on(d),
                                         title: "Meal prep", subtitle: "Cook this week's lunches and dinners",
                                         category: .food, symbol: "frying.pan.fill"))
            }
        }

        out.append(dinner)
        out.append(TimelineBlock(id: "wind", start: MySchedule.windDown.on(d), title: "Wind down",
                                 subtitle: "Phone down · bed by " + MySchedule.bedtime.label,
                                 category: .sleep, symbol: "moon.fill"))
        out += events.filter { $0.occurs(on: d) }.map { $0.block(on: d) }
        return out.sorted { $0.start < $1.start }
    }
}
