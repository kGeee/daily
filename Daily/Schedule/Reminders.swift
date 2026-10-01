import Foundation
import UserNotifications

/// Schedules local notifications for the next week: departures, Sunday meal prep,
/// wind-down, and any of your own events that have reminders on.
enum Reminders {
    static let prefix = "daily-"

    static func requestPermission() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    @MainActor
    static func reschedule(enabled: Bool, planner: DayPlanner, events: [CustomEvent]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let cal = Calendar.current
        let now = Date()
        let lead = Double(MySchedule.reminderLeadMinutes * 60)

        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let remindedEvents = events.filter { $0.remind }
            let blocks = planner.blocks(for: day, lunchNote: nil, dinnerNote: nil, events: remindedEvents)

            for block in blocks {
                let fire: Date
                let title: String
                let body: String

                if block.isDeparture {
                    fire = block.start.addingTimeInterval(-lead)
                    title = block.title
                    body = "Leave in \(MySchedule.reminderLeadMinutes) min · " + block.start.formatted(date: .omitted, time: .shortened)
                } else if block.eventID != nil {
                    fire = block.start.addingTimeInterval(-lead)
                    title = block.title
                    body = "Starts at " + block.start.formatted(date: .omitted, time: .shortened)
                } else if block.id == "prep" {
                    fire = block.start
                    title = "Meal prep time"
                    body = "Cook this week's lunches and dinners."
                } else if block.id == "wind" {
                    fire = block.start
                    title = "Time to wind down"
                    body = "Phone down, bed by 11:30."
                } else {
                    continue
                }

                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: prefix + DayKey.of(day) + "-" + block.id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }
}
