import SwiftUI

struct ClockTime: Hashable {
    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    func on(_ day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var label: String {
        on(Date()).formatted(date: .omitted, time: .shortened)
    }
}

/// Your personal schedule. Edit these to change the timeline.
enum MySchedule {
    static let wake = ClockTime(6, 50)
    static let shuttleOut = ClockTime(7, 45)
    static let caltrainOut = ClockTime(7, 30)       // estimate until live times are added
    static let workStart = ClockTime(8, 30)
    static let lunch = ClockTime(12, 0)
    static let leaveForGym = ClockTime(15, 0)
    static let gymStart = ClockTime(15, 30)
    static let gymEnd = ClockTime(16, 55)
    static let caltrainAfterGym = ClockTime(17, 15) // estimate
    static let shuttleHome = ClockTime(16, 0)
    static let caltrainHome = ClockTime(17, 0)      // estimate
    static let dinner = ClockTime(18, 30)
    static let windDown = ClockTime(23, 0)
    static let prepStart = ClockTime(16, 0)         // Sunday meal prep
    static let prepEnd = ClockTime(18, 0)

    static let shuttleStop = "Your shuttle stop"
    static let eatOutGoalPerWeek = 2

    /// Usual day type for Mon–Fri, in order.
    static let defaultPattern = "shuttle,gym,gym,shuttle,caltrain"
}

enum DayType: String, CaseIterable, Identifiable {
    case shuttle, gym, caltrain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .shuttle: return "Shuttle day"
        case .gym: return "Gym day"
        case .caltrain: return "Caltrain day"
        }
    }

    var short: String {
        switch self {
        case .shuttle: return "Shuttle"
        case .gym: return "Gym"
        case .caltrain: return "Caltrain"
        }
    }

    var color: Color {
        switch self {
        case .shuttle: return Palette.commute
        case .gym: return Palette.gym
        case .caltrain: return Palette.caltrain
        }
    }

    var tint: Color {
        switch self {
        case .shuttle: return Palette.commuteTint
        case .gym: return Palette.gymTint
        case .caltrain: return Palette.caltrainTint
        }
    }
}

enum BlockCategory {
    case sleep, commute, work, food, gym

    var color: Color {
        switch self {
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

    /// weekday: 1 = Sunday … 7 = Saturday. Weekends have no commute.
    func usualType(forWeekday weekday: Int) -> DayType? {
        guard (2...6).contains(weekday) else { return nil }
        let parts = pattern.split(separator: ",").map(String.init)
        let index = weekday - 2
        guard index < parts.count else { return nil }
        return DayType(rawValue: parts[index])
    }

    func type(for date: Date) -> DayType? {
        let key = DayKey.of(date)
        if let override = overrides.first(where: { $0.dayKey == key }),
           let type = DayType(rawValue: override.typeRaw) {
            return type
        }
        return usualType(forWeekday: Calendar.current.component(.weekday, from: date))
    }

    static func updating(pattern: String, weekday: Int, to type: DayType) -> String {
        var parts = pattern.split(separator: ",").map(String.init)
        while parts.count < 5 { parts.append(DayType.shuttle.rawValue) }
        parts[weekday - 2] = type.rawValue
        return parts.joined(separator: ",")
    }

    func blocks(for day: Date, lunchNote: String?, dinnerNote: String?) -> [TimelineBlock] {
        let d = Calendar.current.startOfDay(for: day)
        let weekday = Calendar.current.component(.weekday, from: d)

        var out: [TimelineBlock] = [
            TimelineBlock(id: "wake", start: MySchedule.wake.on(d), title: "Rise and shine", category: .sleep, symbol: "alarm.fill")
        ]
        let lunch = TimelineBlock(id: "lunch", start: MySchedule.lunch.on(d), title: "Lunch",
                                  subtitle: lunchNote ?? "Not logged yet", category: .food, symbol: "fork.knife")
        let dinner = TimelineBlock(id: "dinner", start: MySchedule.dinner.on(d), title: "Dinner",
                                   subtitle: dinnerNote ?? "Not logged yet", category: .food, symbol: "fork.knife")

        switch type(for: d) {
        case .shuttle?:
            out += [
                TimelineBlock(id: "out", start: MySchedule.shuttleOut.on(d), title: "Shuttle to work",
                              subtitle: MySchedule.shuttleStop, category: .commute, symbol: "bus.fill", isDeparture: true),
                TimelineBlock(id: "work", start: MySchedule.workStart.on(d), end: MySchedule.shuttleHome.on(d),
                              title: "Work", category: .work, symbol: "briefcase.fill"),
                lunch,
                TimelineBlock(id: "home", start: MySchedule.shuttleHome.on(d), title: "Shuttle home",
                              subtitle: "From the work stop", category: .commute, symbol: "bus.fill", isDeparture: true)
            ]
        case .gym?:
            out += [
                TimelineBlock(id: "out", start: MySchedule.shuttleOut.on(d), title: "Shuttle to work",
                              subtitle: MySchedule.shuttleStop, category: .commute, symbol: "bus.fill", isDeparture: true),
                TimelineBlock(id: "work", start: MySchedule.workStart.on(d), end: MySchedule.leaveForGym.on(d),
                              title: "Work", category: .work, symbol: "briefcase.fill"),
                lunch,
                TimelineBlock(id: "go", start: MySchedule.leaveForGym.on(d), title: "Leave for gym",
                              subtitle: "Skip the 4:00 shuttle today", category: .gym, symbol: "arrow.right", isDeparture: true),
                TimelineBlock(id: "gym", start: MySchedule.gymStart.on(d), end: MySchedule.gymEnd.on(d),
                              title: "Gym", category: .gym, symbol: "dumbbell.fill"),
                TimelineBlock(id: "home", start: MySchedule.caltrainAfterGym.on(d), title: "Caltrain home",
                              subtitle: "From Sunnyvale · next train after gym", category: .commute,
                              symbol: "tram.fill", isEstimate: true, isDeparture: true)
            ]
        case .caltrain?:
            out += [
                TimelineBlock(id: "out", start: MySchedule.caltrainOut.on(d), title: "Caltrain to Sunnyvale",
                              category: .commute, symbol: "tram.fill", isEstimate: true, isDeparture: true),
                TimelineBlock(id: "work", start: MySchedule.workStart.on(d), end: MySchedule.caltrainHome.on(d),
                              title: "Work", category: .work, symbol: "briefcase.fill"),
                lunch,
                TimelineBlock(id: "home", start: MySchedule.caltrainHome.on(d), title: "Caltrain home",
                              subtitle: "From Sunnyvale", category: .commute, symbol: "tram.fill",
                              isEstimate: true, isDeparture: true)
            ]
        case nil:
            out.append(lunch)
            if weekday == 1 {
                out.append(TimelineBlock(id: "prep", start: MySchedule.prepStart.on(d), end: MySchedule.prepEnd.on(d),
                                         title: "Meal prep", subtitle: "Cook this week's lunches and dinners",
                                         category: .food, symbol: "frying.pan.fill"))
            }
        }

        out.append(dinner)
        out.append(TimelineBlock(id: "wind", start: MySchedule.windDown.on(d), title: "Wind down",
                                 subtitle: "Phone down · bed by 11:30", category: .sleep, symbol: "moon.fill"))
        return out.sorted { $0.start < $1.start }
    }
}
