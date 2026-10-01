import SwiftUI
import SwiftData

struct CommuteView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("remindersOn") private var remindersOn = false

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }

    private struct Leg: Identifiable {
        let id = UUID()
        let time: String
        let title: String
        let subtitle: String
        let isToday: Bool
    }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let today = Calendar.current.startOfDay(for: tl.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(eyebrow: tl.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                 title: "Commute")
                    if let type = planner.type(for: today) {
                        Picker("Day type", selection: Binding(
                            get: { type },
                            set: { setType($0, on: today) }
                        )) {
                            ForEach(DayType.allCases) { t in
                                Text(t.short).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        morningCard(type: type, today: today, now: tl.date)
                        afternoonCard(type: type)
                    } else {
                        Text("No commute today. Enjoy the weekend.")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                            .card()
                    }
                    remindersCard
                    weekCard
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
        }
    }

    private func setType(_ type: DayType, on day: Date) {
        let key = DayKey.of(day)
        if let existing = overrides.first(where: { $0.dayKey == key }) {
            existing.typeRaw = type.rawValue
        } else {
            context.insert(DayTypeOverride(dayKey: key, typeRaw: type.rawValue))
        }
    }

    // MARK: Morning

    private func morningCard(type: DayType, today: Date, now: Date) -> some View {
        let isCaltrain = type == .caltrain
        let departure = (isCaltrain ? MySchedule.caltrainOut : MySchedule.shuttleOut).on(today)
        let minutes = Int(departure.timeIntervalSince(now) / 60)

        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Morning · to work", color: Palette.onAccent.opacity(0.85))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((isCaltrain ? "~" : "") + departure.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 34, weight: .heavy))
                    Text(isCaltrain ? "Caltrain → Sunnyvale" : "Work shuttle")
                        .font(.subheadline.weight(.semibold))
                    Text(isCaltrain ? "Live times coming soon" : MySchedule.shuttleStop)
                        .font(.footnote)
                        .opacity(0.85)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if minutes >= 0 {
                        Text("Leave in").font(.caption).opacity(0.85)
                        Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min")
                            .font(.system(size: 24, weight: .heavy))
                    } else {
                        Text("Departed").font(.subheadline.weight(.bold)).opacity(0.85)
                    }
                }
            }
        }
        .foregroundStyle(Palette.onAccent)
        .card(padding: 18, fill: Palette.commute)
    }

    // MARK: Afternoon

    private func legs(for type: DayType) -> [Leg] {
        switch type {
        case .shuttle:
            return [
                Leg(time: MySchedule.shuttleHome.label, title: "Shuttle home", subtitle: "From the work stop", isToday: true),
                Leg(time: "~" + MySchedule.caltrainHome.label, title: "Caltrain", subtitle: "Backup if you miss it", isToday: false)
            ]
        case .gym:
            return [
                Leg(time: MySchedule.leaveForGym.label, title: "Leave work for gym", subtitle: "Skip the 4:00 shuttle", isToday: true),
                Leg(time: "~" + MySchedule.caltrainAfterGym.label, title: "Caltrain home",
                    subtitle: "From Sunnyvale · next train after gym", isToday: true)
            ]
        case .caltrain:
            return [
                Leg(time: "~" + MySchedule.caltrainHome.label, title: "Caltrain from Sunnyvale",
                    subtitle: "Live times coming soon", isToday: true),
                Leg(time: MySchedule.shuttleHome.label, title: "Shuttle home", subtitle: "Backup if plans change", isToday: false)
            ]
        }
    }

    private func afternoonCard(type: DayType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Afternoon · home")
            ForEach(legs(for: type)) { leg in
                HStack(spacing: 12) {
                    Text(leg.time)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.title).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                        Text(leg.subtitle).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if leg.isToday {
                        Text("TODAY").font(.caption2.weight(.heavy)).foregroundStyle(Palette.commuteText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(leg.isToday ? Palette.commuteTint : Palette.card2,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(leg.isToday ? Palette.commute : Color.clear, lineWidth: 2)
                )
            }
        }
        .card()
    }

    // MARK: Reminders

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { remindersOn },
                set: { newValue in
                    if newValue {
                        Task { remindersOn = await Reminders.requestPermission() }
                    } else {
                        remindersOn = false
                    }
                }
            )) {
                Text("Remind me \(MySchedule.reminderLeadMinutes) min before I leave")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.commute)
            Text("Also reminds you about Sunday meal prep, wind-down, and your own events.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .card()
    }

    // MARK: Usual week

    private var weekCard: some View {
        let days: [(String, Int)] = [("MON", 2), ("TUE", 3), ("WED", 4), ("THU", 5), ("FRI", 6)]
        let todayWeekday = Calendar.current.component(.weekday, from: Date())

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Your usual week")
                Spacer()
                Text("Tap a day to change")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.1) { day in
                    let name = day.0
                    let weekday = day.1
                    let type = planner.usualType(forWeekday: weekday) ?? .shuttle
                    Menu {
                        ForEach(DayType.allCases) { t in
                            Button(t.title) {
                                pattern = DayPlanner.updating(pattern: pattern, weekday: weekday, to: t)
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(name).font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                            Text(type.short).font(.caption.weight(.bold)).foregroundStyle(Palette.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(type.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(weekday == todayWeekday ? Palette.ink : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }
        .card()
    }
}
