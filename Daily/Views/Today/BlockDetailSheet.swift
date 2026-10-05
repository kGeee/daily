import SwiftUI
import SwiftData

/// Details for any block on the timeline (routine steps, meals, wake up, wind down…).
/// Custom events open `EventEditor` instead.
struct BlockDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var checks: [BlockCheck]
    @Query private var plans: [MealPlan]

    let block: TimelineBlock
    let day: Date

    @State private var time: Date
    @State private var showTime = false
    @State private var logDraft: LogDraft?
    @State private var showSettings = false

    init(block: TimelineBlock, day: Date) {
        self.block = block
        self.day = day
        _time = State(initialValue: block.start)
    }

    private var dayKey: String { DayKey.of(day) }
    private var routineType: DayType? { block.routineType }
    private var hasOverride: Bool { Routines.overrides(for: dayKey)[block.id] != nil }

    private var isDone: Bool {
        checks.contains { $0.dayKey == dayKey && $0.blockID == block.id }
    }

    private func toggleDone() {
        if let existing = checks.first(where: { $0.dayKey == dayKey && $0.blockID == block.id }) {
            context.delete(existing)
        } else {
            context.insert(BlockCheck(dayKey: dayKey, blockID: block.id))
        }
    }

    private var timeText: String {
        var s = block.start.formatted(date: .omitted, time: .shortened)
        if let end = block.end { s += " – " + end.formatted(date: .omitted, time: .shortened) }
        if block.isEstimate { s += " (est.)" }
        return s
    }

    private var dayLabel: String {
        Calendar.current.isDateInToday(day) ? "today" : day.formatted(.dateTime.weekday(.wide))
    }

    private var relativeDay: String? {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return nil
    }

    private var mealSlot: MealSlot? {
        switch block.id {
        case "lunch": return .lunch
        case "dinner": return .dinner
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            DetailSheetLayout {
                DetailHero(background: block.category.hero, symbol: block.symbol, iconColor: block.category.color,
                           timeText: timeText, badges: routineType == nil ? [] : ["arrow.triangle.2.circlepath"],
                           done: isDone, onToggle: toggleDone, onClose: { dismiss() }) {
                    Text(block.title)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            } content: {
                DetailCard {
                    DetailRowLabel(symbol: "calendar", tint: block.category.color,
                                   title: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                                   value: relativeDay, chevron: false)
                    DetailDivider()
                    if routineType != nil {
                        DetailExpandableRow(symbol: "clock.fill", tint: block.category.color, title: timeText,
                                            value: hasOverride ? "Changed" : nil, expanded: $showTime) {
                            VStack(spacing: 10) {
                                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                                    .wheelDatePickerStyle()
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                DetailPrimaryButton(title: "Move to " + time.formatted(date: .omitted, time: .shortened)
                                                    + " " + dayLabel, fill: block.category.color) {
                                    moveJustThisDay()
                                }
                            }
                        }
                    } else {
                        DetailRowLabel(symbol: "clock.fill", tint: block.category.color, title: timeText, chevron: false)
                    }
                    if let leaveBy = block.leaveBy, leaveBy != block.start {
                        DetailDivider()
                        DetailRowLabel(symbol: "figure.walk", tint: block.category.color, title: "Leave by",
                                       value: leaveBy.formatted(date: .omitted, time: .shortened), chevron: false)
                    }
                    if !block.subtitle.isEmpty {
                        DetailDivider()
                        DetailRowLabel(symbol: "text.alignleft", tint: block.category.color, title: block.subtitle,
                                       chevron: false)
                    }
                }

                if let type = routineType {
                    DetailCard {
                        Button {
                            Routines.setOverride(StepOverride(skipped: true), step: block.id, dayKey: dayKey)
                            Pref.bump()
                            dismiss()
                        } label: {
                            DetailRowLabel(symbol: "forward.end.fill", tint: Palette.danger, title: "Skip it " + dayLabel,
                                           chevron: false)
                        }
                        .buttonStyle(.plain)
                        if hasOverride {
                            DetailDivider()
                            Button {
                                Routines.setOverride(nil, step: block.id, dayKey: dayKey)
                                Pref.bump()
                                dismiss()
                            } label: {
                                DetailRowLabel(symbol: "arrow.uturn.backward", tint: block.category.color,
                                               title: "Back to the usual", chevron: false)
                            }
                            .buttonStyle(.plain)
                        }
                        DetailDivider()
                        NavigationLink {
                            RoutineEditorView(type: type)
                        } label: {
                            DetailRowLabel(symbol: "list.bullet", tint: block.category.color,
                                           title: "Change the \(type.title) routine")
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Moving or skipping only changes " + dayLabel + ". Later steps that follow this one move with it.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                } else {
                    DetailCard {
                        if let slot = mealSlot {
                            Button {
                                let planned = plans.first { $0.dayKey == dayKey && $0.slot == slot }
                                let name = planned.map { $0.isEatingOut ? "" : $0.title } ?? ""
                                logDraft = LogDraft(slot: slot, source: planned?.isEatingOut == true ? .out : .prepped,
                                                    name: name)
                            } label: {
                                DetailRowLabel(symbol: "fork.knife", tint: Palette.food, title: "Log \(slot.title.lowercased())")
                            }
                            .buttonStyle(.plain)
                            DetailDivider()
                        }
                        Button {
                            showSettings = true
                        } label: {
                            DetailRowLabel(symbol: "gearshape.fill", tint: Palette.muted, title: "Change your usual times")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .sheet(item: $logDraft) { draft in
            LogMealSheet(draft: draft)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func moveJustThisDay() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        Routines.setOverride(StepOverride(time: minutes), step: block.id, dayKey: dayKey)
        Pref.bump()
        dismiss()
    }
}
