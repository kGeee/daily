import Foundation

/// Data shared between the app, its widgets and the share extension, through an App Group.
/// If the App Group isn't set up, this quietly falls back to the app's own storage.
enum SharedStore {
    static let groupID = "group.com.kgeee.daily"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    // MARK: Snapshot the app writes for widgets

    struct Departure: Codable, Hashable {
        var title: String
        var subtitle: String
        var start: Date
        var leaveBy: Date
        var isEstimate: Bool
        var symbol: String
    }

    /// One row on the timeline widget.
    struct Item: Codable, Hashable, Identifiable {
        var blockID: String
        var dayKey: String
        var title: String
        var subtitle: String
        var start: Date
        var end: Date?
        var symbol: String
        /// commute, gym, food, sleep, work, general
        var category: String
        var done: Bool
        var id: String { dayKey + "|" + blockID }
    }

    struct Snapshot: Codable {
        var updated: Date = Date()
        var dayKey: String = ""
        var dayType: String? = nil
        var departures: [Departure] = []
        var waterOz: Int = 0
        var waterGoal: Int = 100
        var calories: Int = 0
        var calorieGoal: Int = 2200
        var protein: Int = 0
        var proteinGoal: Int = 140
        var meals: [String] = []
        var items: [Item]? = nil
    }

    private static let snapshotKey = "widgetSnapshot"

    static func save(_ snapshot: Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    static func load() -> Snapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return snapshot
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Water added from the widget (merged into the app's log when it opens)

    struct PendingWater: Codable {
        var dayKey: String
        var ounces: Int
    }

    private static let pendingWaterKey = "pendingWater"

    static func addPendingWater(_ ounces: Int) {
        var list = pendingWater()
        list.append(PendingWater(dayKey: todayKey(), ounces: ounces))
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: pendingWaterKey) }
    }

    static func pendingWater() -> [PendingWater] {
        guard let data = defaults.data(forKey: pendingWaterKey),
              let list = try? JSONDecoder().decode([PendingWater].self, from: data) else { return [] }
        return list
    }

    static func takePendingWater() -> [PendingWater] {
        let list = pendingWater()
        defaults.removeObject(forKey: pendingWaterKey)
        return list
    }

    /// Water shown on the widget: what the app last saved plus anything added from the widget since.
    static func widgetWaterToday() -> Int {
        let snapshot = load()
        let base = snapshot.dayKey == todayKey() ? snapshot.waterOz : 0
        return base + pendingWater().filter { $0.dayKey == todayKey() }.reduce(0) { $0 + $1.ounces }
    }

    // MARK: Links shared from Instagram (or anywhere) via the share sheet

    struct PendingImport: Codable, Identifiable {
        var id = UUID()
        var link: String
        var text: String
    }

    private static let pendingImportsKey = "pendingImports"

    static func addPendingImport(link: String, text: String) {
        var list = pendingImports()
        list.append(PendingImport(link: link, text: text))
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: pendingImportsKey) }
    }

    static func pendingImports() -> [PendingImport] {
        guard let data = defaults.data(forKey: pendingImportsKey),
              let list = try? JSONDecoder().decode([PendingImport].self, from: data) else { return [] }
        return list
    }

    static func takePendingImports() -> [PendingImport] {
        let list = pendingImports()
        defaults.removeObject(forKey: pendingImportsKey)
        return list
    }

    // MARK: Check-offs tapped on the timeline widget (merged when the app opens)

    private static let pendingChecksKey = "pendingChecks"

    /// Tapping twice cancels out.
    static func togglePendingCheck(_ itemID: String) {
        var set = Set(defaults.stringArray(forKey: pendingChecksKey) ?? [])
        if set.contains(itemID) { set.remove(itemID) } else { set.insert(itemID) }
        defaults.set(Array(set), forKey: pendingChecksKey)
    }

    static func pendingChecks() -> Set<String> {
        Set(defaults.stringArray(forKey: pendingChecksKey) ?? [])
    }

    static func takePendingChecks() -> Set<String> {
        let set = pendingChecks()
        defaults.removeObject(forKey: pendingChecksKey)
        return set
    }

    // MARK: "+" on the widget asks the app to open the new-event screen

    private static let openAddEventKey = "openAddEvent"

    static func requestAddEvent() { defaults.set(true, forKey: openAddEventKey) }

    static func takeAddEventRequest() -> Bool {
        let value = defaults.bool(forKey: openAddEventKey)
        defaults.removeObject(forKey: openAddEventKey)
        return value
    }
}
