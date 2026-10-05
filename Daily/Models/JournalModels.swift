import SwiftUI
import SwiftData
import UserNotifications

enum Mood: String, CaseIterable, Identifiable {
    case great, good, okay, rough
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .great: return "sun.max.fill"
        case .good: return "sun.min.fill"
        case .okay: return "cloud.sun.fill"
        case .rough: return "cloud.rain.fill"
        }
    }

    var color: Color {
        switch self {
        case .great: return Palette.food
        case .good: return Palette.commute
        case .okay: return Palette.gym
        case .rough: return Palette.sleep
        }
    }
}

/// A photo check-in: a picture of how the day is going, with a mood and a line about it.
@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    @Attribute(.externalStorage) var photo: Data?
    var caption: String = ""
    var moodRaw: String = ""

    init(date: Date = .now, photo: Data?, caption: String = "", mood: Mood? = nil) {
        self.id = UUID()
        self.date = date
        self.photo = photo
        self.caption = caption
        self.moodRaw = mood?.rawValue ?? ""
    }

    var mood: Mood? { Mood(rawValue: moodRaw) }
}

/// One thing in the journal feed: a check-in, or a meal you took a photo of.
struct JournalItem: Identifiable {
    enum Kind { case checkIn(JournalEntry), meal(FoodEntry) }
    let kind: Kind
    let date: Date
    let photo: Data?

    var id: String {
        switch kind {
        case .checkIn(let e): return "j-" + e.id.uuidString
        case .meal(let m): return "m-\(m.persistentModelID.hashValue)-\(m.date.timeIntervalSince1970)"
        }
    }

    /// Check-ins and photographed meals, newest first, grouped by day (newest day first).
    static func days(entries: [JournalEntry], meals: [FoodEntry]) -> [(day: Date, items: [JournalItem])] {
        var items = entries.map { JournalItem(kind: .checkIn($0), date: $0.date, photo: $0.photo) }
        items += meals.filter { $0.photo != nil }.map { JournalItem(kind: .meal($0), date: $0.date, photo: $0.photo) }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}

/// The daily "midday check-in" reminder.
enum CheckIn {
    static let onKey = "pref.checkInOn"
    static let timeKey = "pref.checkInTime"
    static let defaultTime = 12 * 60 + 30
    static let notificationID = "checkin.midday"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var time: Int { UserDefaults.standard.object(forKey: timeKey) as? Int ?? defaultTime }

    /// Show the check-in card from an hour before the reminder until mid-afternoon, until you've checked in.
    static func shouldPrompt(at now: Date, entries: [JournalEntry]) -> Bool {
        let cal = Calendar.current
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        guard minutes >= time - 60 && minutes < max(time + 4 * 60, 17 * 60) else { return false }
        return !entries.contains { cal.isDate($0.date, inSameDayAs: now) }
    }

    static func updateReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard isOn else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Midday check-in"
        content.body = "How's today going? Snap a photo of whatever's in front of you."
        content.sound = .default
        var parts = DateComponents()
        parts.hour = time / 60
        parts.minute = time % 60
        let request = UNNotificationRequest(identifier: notificationID, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true))
        try? await center.add(request)
    }
}
