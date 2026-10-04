import SwiftUI
import SwiftData

/// Say (or type) what's going on for a day; AI turns it into events you can review and add.
struct VoicePlanSheet: View {
    enum DayChoice: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow", pick = "Pick a day" }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var events: [CustomEvent]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    @StateObject private var speech = SpeechRecognizer()
    @State private var choice: DayChoice
    @State private var pickedDay: Date
    @State private var drafts: [EventDraft] = []
    @State private var summary = ""
    @State private var planning = false
    @State private var errorText: String?
    @State private var editing: UUID?

    init(day: Date = Date()) {
        let cal = Calendar.current
        let initial: DayChoice = cal.isDateInToday(day) ? .today : (cal.isDateInTomorrow(day) ? .tomorrow : .pick)
        _choice = State(initialValue: initial)
        _pickedDay = State(initialValue: cal.startOfDay(for: day))
    }

    private var day: Date {
        let cal = Calendar.current
        switch choice {
        case .today: return cal.startOfDay(for: Date())
        case .tomorrow: return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        case .pick: return cal.startOfDay(for: pickedDay)
        }
    }

    private var existingBlocks: [TimelineBlock] {
        DayPlanner(pattern: pattern, overrides: overrides)
            .blocks(for: day, lunchNote: nil, dinnerNote: nil, events: events)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if drafts.isEmpty {
                        inputView
                    } else {
                        previewView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.snappy(duration: 0.3), value: drafts.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(drafts.isEmpty ? "Cancel" : "Back") {
                        if drafts.isEmpty { speech.stop(); dismiss() } else { drafts = [] }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .onDisappear { speech.stop() }
    }

    // MARK: Talking

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Plan out loud", color: Palette.commuteText)
                Text("What's on " + (choice == .today ? "today" : day.formatted(.dateTime.weekday(.wide))) + "?")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Palette.ink)
            }
            PillSegment(DayChoice.allCases, selection: $choice) { $0.rawValue }
            if choice == .pick {
                DatePicker("Day", selection: $pickedDay, in: Date()..., displayedComponents: .date)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            TextField("e.g. Niners game from 1 to 4, then groceries and meal prep, gym, laundry, and some work at night",
                      text: $speech.transcript, axis: .vertical)
                .font(.system(size: 19))
                .lineLimit(6...14)
                .foregroundStyle(Palette.ink)
                .padding(18)
                .frame(minHeight: 200, alignment: .topLeading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            levelMeter
                .frame(height: 50)
                .frame(maxWidth: .infinity)

            if let message = speech.errorText ?? errorText {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Palette.gymText)
            }
        }
    }

    private var levelMeter: some View {
        HStack(spacing: 4) {
            ForEach(0..<18, id: \.self) { i in
                let wobble = (sin(Double(i) * 1.7) + 1) / 2
                Capsule()
                    .fill(Palette.commute.opacity(speech.isListening ? 0.4 + 0.6 * wobble : 0.25))
                    .frame(width: 5, height: speech.isListening ? max(6, CGFloat(speech.level) * 50 * (0.4 + wobble)) : 6)
            }
        }
        .animation(.easeOut(duration: 0.12), value: speech.level)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if drafts.isEmpty {
                HStack(spacing: 14) {
                    Button {
                        speech.toggle()
                    } label: {
                        ZStack {
                            Circle().fill(speech.isListening ? Palette.danger : Palette.commute)
                            if speech.isListening {
                                RoundedRectangle(cornerRadius: 5).fill(Palette.onAccent).frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Palette.onAccent)
                            }
                        }
                        .frame(width: 72, height: 72)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact, trigger: speech.isListening)
                    .accessibilityLabel(speech.isListening ? "Stop listening" : "Start listening")

                    DetailPrimaryButton(title: planning ? "Planning…" : "Plan it", symbol: "sparkles", fill: Palette.ink) {
                        runPlan()
                    }
                    .disabled(planning || speech.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(speech.transcript.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                }
            } else {
                let count = drafts.filter(\.include).count
                DetailPrimaryButton(title: "Add \(count) event\(count == 1 ? "" : "s") to " + dayName, symbol: "plus",
                                    fill: Palette.commute) {
                    addEvents()
                }
                .disabled(count == 0)
                .opacity(count == 0 ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.bg)
    }

    private var dayName: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "today" }
        if cal.isDateInTomorrow(day) { return "tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: Reviewing

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), color: Palette.commuteText)
                Text("Here's your plan")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                if !summary.isEmpty {
                    Text(summary).font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            VStack(spacing: 0) {
                ForEach($drafts) { $draft in
                    draftRow($draft)
                    if draft.id != drafts.last?.id {
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Tap a time to change it. Untick anything you don't want.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }

    private func draftRow(_ draft: Binding<EventDraft>) -> some View {
        let d = draft.wrappedValue
        let open = editing == d.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: d.kind.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(d.kind.category.color)
                    .frame(width: 46, height: 46)
                    .background(Palette.circle, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Button {
                        withAnimation(.snappy) { editing = open ? nil : d.id }
                    } label: {
                        Text(d.start.formatted(date: .omitted, time: .shortened) + " – " + d.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.commuteText)
                    }
                    .buttonStyle(.plain)
                    TextField("Title", text: draft.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(d.include ? Palette.ink : Palette.faint)
                    if !d.note.isEmpty {
                        Text(d.note).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Button {
                    draft.wrappedValue.include.toggle()
                } label: {
                    Image(systemName: d.include ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(d.include ? Palette.commute : Palette.idle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.include ? "Don't add \(d.title)" : "Add \(d.title)")
            }
            if open {
                HStack {
                    DatePicker("Start", selection: draft.start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: draft.end, in: d.start..., displayedComponents: .hourAndMinute)
                }
                .labelsHidden()
                .padding(.leading, 58)
            }
        }
        .padding(.vertical, 10)
        .opacity(d.include ? 1 : 0.6)
    }

    // MARK: Actions

    private func runPlan() {
        speech.stop()
        planning = true
        errorText = nil
        let text = speech.transcript
        let target = day
        let blocks = existingBlocks
        Task {
            do {
                let plan = try await VoicePlanner.plan(text: text, day: target, blocks: blocks)
                let made = VoicePlanner.drafts(from: plan, on: target)
                if made.isEmpty {
                    errorText = "Couldn't find any events in that. Try saying times or tasks."
                } else {
                    summary = plan.summary ?? ""
                    drafts = made
                }
            } catch {
                errorText = error.localizedDescription
            }
            planning = false
        }
    }

    private func addEvents() {
        for d in drafts where d.include {
            let title = d.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            context.insert(CustomEvent(title: title, note: d.note, start: d.start, durationMinutes: max(d.minutes, 0),
                                       kind: d.kind, repeats: .none, remind: true))
        }
        dismiss()
    }
}
