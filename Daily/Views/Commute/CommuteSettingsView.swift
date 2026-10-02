import SwiftUI
import SwiftData

/// Everything about getting to and from work: routines for each kind of day, the usual week,
/// one-off day changes, timetables, live Caltrain and reminders.
struct CommuteSettingsView: View {
    /// True when pushed inside another settings screen (no own NavigationStack / Done button).
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage(Pref.reminderLead) private var reminderLead = Pref.reminderLeadDefault
    @AppStorage(Pref.liveStationName) private var liveStationName = ""
    @AppStorage(Pref.directionToWork) private var directionToWork = Pref.directionToWorkDefault
    @AppStorage(Pref.revision) private var revision = 0
    @State private var key511 = Keychain.read(Keychain.fiveOneOne) ?? ""
    @State private var timetables: [Timetable] = Timetables.all

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack {
                form
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    private var form: some View {
        let _ = revision
        return Form {
            Section {
                ForEach(DayType.allCases) { type in
                    NavigationLink {
                        RoutineEditorView(type: type)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Circle().fill(type.color).frame(width: 8, height: 8)
                                Text(type.title).font(.body.weight(.semibold))
                            }
                            Text(routineSummary(type))
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(2)
                        }
                    }
                }
            } header: {
                Text("Your routines")
            } footer: {
                Text("What you do on each kind of day, step by step: shuttle, VTA, Caltrain, gym, hanging out. Tap one to change times or steps.")
            }

            Section {
                ForEach(weekdays, id: \.self) { weekday in
                    Picker(weekdayName(weekday), selection: Binding(
                        get: { planner.usualType(forWeekday: weekday) ?? .shuttle },
                        set: { pattern = DayPlanner.updating(pattern: pattern, weekday: weekday, to: $0) }
                    )) {
                        ForEach(DayType.allCases) { t in Text(t.title).tag(t) }
                    }
                }
            } header: {
                Text("Your usual week")
            }

            Section {
                ForEach(thisWeek, id: \.self) { day in
                    Picker(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), selection: Binding(
                        get: { planner.type(for: day) ?? .shuttle },
                        set: { setType($0, on: day) }
                    )) {
                        ForEach(DayType.allCases) { t in Text(t.title).tag(t) }
                    }
                }
            } header: {
                Text("This week")
            } footer: {
                Text("Changes here only affect that one day.")
            }

            Section {
                ForEach(timetables) { table in
                    NavigationLink {
                        TimetableEditorView(timetable: table) { updated in
                            if let index = timetables.firstIndex(where: { $0.id == updated.id }) {
                                timetables[index] = updated
                                Timetables.save(timetables)
                                Pref.bump()
                            }
                        }
                    } label: {
                        HStack {
                            Text(table.name)
                            Spacer()
                            Text("\(Timetables.times(table.id).count) times").foregroundStyle(Palette.muted)
                        }
                    }
                }
                .onDelete { offsets in
                    let builtIn = Set(Timetable.defaults.map { $0.id })
                    let removable = offsets.filter { !builtIn.contains(timetables[$0].id) }
                    timetables.remove(atOffsets: IndexSet(removable))
                    Timetables.save(timetables)
                }
                Button("Add a timetable") {
                    let table = Timetable(id: UUID().uuidString, name: "New timetable")
                    timetables.append(table)
                    Timetables.save(timetables)
                }
            } header: {
                Text("Timetables")
            } footer: {
                Text("Departure times for Caltrain, the Sunnyvale station shuttle, or anything else. Routine steps can pick the next one automatically.")
            }

            Section {
                SecureField("511.org API key", text: $key511)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: key511) { _, newValue in
                        Keychain.save(newValue, account: Keychain.fiveOneOne)
                    }
                NavigationLink {
                    StationPickerView()
                } label: {
                    HStack {
                        Text("Home station")
                        Spacer()
                        Text(liveStationName.isEmpty ? "Choose" : liveStationName).foregroundStyle(Palette.muted)
                    }
                }
                Picker("To Sunnyvale I ride", selection: $directionToWork) {
                    Text("Southbound").tag("S")
                    Text("Northbound").tag("N")
                }
                if let url = URL(string: "https://511.org/open-data/token") {
                    Link("Get a free 511 key", destination: url)
                }
            } header: {
                Text("Live Caltrain")
            } footer: {
                Text("Shows live departures and delays for your next Caltrain step, including Mountain View on nights you're there.")
            }

            Section {
                Toggle("Remind me before I need to leave", isOn: Binding(
                    get: { remindersOn },
                    set: { newValue in
                        if newValue {
                            Task { remindersOn = await Reminders.requestPermission() }
                        } else {
                            remindersOn = false
                        }
                    }
                ))
                MinutesStepper(title: "How early", minutes: $reminderLead, range: 0...60)
            } header: {
                Text("Reminders")
            } footer: {
                Text("Also reminds you about Sunday meal prep, wind-down, packing your gym bag, and your own events.")
            }
        }
        .navigationTitle("Commute")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Pref.bump() }
    }

    private let weekdays = [2, 3, 4, 5, 6]

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    private var thisWeek: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { (2...6).contains(cal.component(.weekday, from: $0)) && $0 >= today }
    }

    private func setType(_ type: DayType, on day: Date) {
        let key = DayKey.of(day)
        if let existing = overrides.first(where: { $0.dayKey == key }) {
            existing.typeRaw = type.rawValue
        } else {
            context.insert(DayTypeOverride(dayKey: key, typeRaw: type.rawValue))
        }
    }

    private func routineSummary(_ type: DayType) -> String {
        RoutineResolver.resolve(Routines.steps(for: type))
            .filter { $0.step.isDeparture || $0.step.kind == .gym || $0.step.kind == .hangout }
            .map { ($0.isEstimate ? "~" : "") + ClockTime(minutes: $0.start).label + " " + $0.step.title }
            .joined(separator: " · ")
    }
}

// MARK: - Routine editor

struct RoutineEditorView: View {
    let type: DayType
    @State private var steps: [RoutineStep] = []
    @State private var confirmReset = false

    var body: some View {
        let resolved = Dictionary(RoutineResolver.resolve(steps).map { ($0.step.id, $0) }, uniquingKeysWith: { first, _ in first })

        List {
            Section {
                ForEach(steps) { step in
                    NavigationLink {
                        StepEditorView(step: step, isNew: false) { updated in
                            if let index = steps.firstIndex(where: { $0.id == updated.id }) {
                                steps[index] = updated
                                persist()
                            }
                        } onDelete: {
                            steps.removeAll { $0.id == step.id }
                            persist()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: step.kind.symbol)
                                .foregroundStyle(step.kind.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.body.weight(.semibold))
                                Text(describe(step))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if let r = resolved[step.id] {
                                Text((r.isEstimate ? "~" : "") + ClockTime(minutes: r.start).label)
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    steps.remove(atOffsets: offsets)
                    persist()
                }
                .onMove { from, to in
                    steps.move(fromOffsets: from, toOffset: to)
                    persist()
                }
                NavigationLink {
                    StepEditorView(step: RoutineStep(title: "", kind: .vta, time: 17 * 60), isNew: true) { added in
                        steps.append(added)
                        persist()
                    } onDelete: {}
                } label: {
                    Label("Add a step", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Steps run in order. A step set to \"right after the previous step\" or \"next departure after the previous step\" moves automatically when an earlier step changes. Times shown are for today.")
            }

            Section {
                Button("Reset to the default routine", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { steps = Routines.steps(for: type) }
        .confirmationDialog("Reset \(type.title)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                Routines.reset(type)
                steps = Routines.steps(for: type)
                Pref.bump()
            }
        }
    }

    private func persist() {
        Routines.save(steps, for: type)
        Pref.bump()
    }

    private func describe(_ step: RoutineStep) -> String {
        var parts: [String] = [step.kind.title]
        switch step.timing {
        case .fixed: break
        case .afterPrevious: parts.append(step.gap > 0 ? "\(step.gap) min after previous" : "after previous")
        case .firstAfter:
            parts.append("next on " + Timetables.name(step.timetableID ?? ""))
        case .lastBefore:
            parts.append("last on " + Timetables.name(step.timetableID ?? "") + " by " + ClockTime(minutes: step.time).label)
        }
        if let end = step.endTime {
            parts.append("until " + ClockTime(minutes: end).label)
        } else if step.duration > 0 {
            parts.append("\(step.duration) min")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Step editor

struct StepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSave: (RoutineStep) -> Void
    let onDelete: () -> Void
    @State private var step: RoutineStep
    @State private var hasEndTime: Bool

    init(step: RoutineStep, isNew: Bool, onSave: @escaping (RoutineStep) -> Void, onDelete: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _step = State(initialValue: step)
        _hasEndTime = State(initialValue: step.endTime != nil)
    }

    private var timetables: [Timetable] { Timetables.all }

    var body: some View {
        Form {
            Section {
                TextField("What is it? (e.g. VTA to Mountain View)", text: $step.title)
                Picker("Type", selection: $step.kind) {
                    ForEach(StepKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .onChange(of: step.kind) { _, kind in
                    if isNew { step.isDeparture = kind.isTransit }
                }
                TextField("Note (stop, station, place)", text: $step.note)
            }

            Section {
                Picker("When", selection: $step.timing) {
                    ForEach(StepTiming.allCases) { t in Text(t.title).tag(t) }
                }
                switch step.timing {
                case .fixed:
                    TimeField(title: "Time", minutes: $step.time)
                case .afterPrevious:
                    MinutesStepper(title: "Gap after previous", minutes: $step.gap, range: 0...120)
                case .firstAfter:
                    timetablePicker
                    Toggle("Right after the previous step", isOn: $step.readyAfterPrevious)
                    if !step.readyAfterPrevious {
                        TimeField(title: "Ready at", minutes: $step.time)
                    }
                case .lastBefore:
                    timetablePicker
                    TimeField(title: "Leaves no later than", minutes: $step.time)
                }
            } header: {
                Text("Timing")
            } footer: {
                Text(timingHelp)
            }

            Section("How long") {
                Toggle("Ends at a set time", isOn: $hasEndTime)
                if hasEndTime {
                    TimeField(title: "Ends at", minutes: Binding(
                        get: { step.endTime ?? (step.time + 60) },
                        set: { step.endTime = $0 }
                    ))
                } else {
                    MinutesStepper(title: "Takes", minutes: $step.duration, range: 0...300)
                }
            }

            Section {
                Toggle("It's a departure", isOn: $step.isDeparture)
                if step.isDeparture {
                    MinutesStepper(title: "Time to get to the stop", minutes: $step.walkMinutes, range: 0...60)
                }
            } footer: {
                Text("Departures get a \"leave by\" time, the Lock Screen countdown and reminders.")
            }

            if !isNew {
                Section {
                    Button("Delete step", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New step" : "Edit step")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var saved = step
                    if !hasEndTime { saved.endTime = nil } else if saved.endTime == nil { saved.endTime = saved.time + 60 }
                    if saved.usesTimetable && saved.timetableID == nil { saved.timetableID = timetables.first?.id }
                    if saved.title.trimmingCharacters(in: .whitespaces).isEmpty { saved.title = saved.kind.title }
                    onSave(saved)
                    dismiss()
                }
            }
        }
    }

    private var timetablePicker: some View {
        Picker("Timetable", selection: Binding(
            get: { step.timetableID ?? timetables.first?.id ?? "" },
            set: { step.timetableID = $0 }
        )) {
            ForEach(timetables) { t in Text(t.name).tag(t.id) }
        }
    }

    private var timingHelp: String {
        switch step.timing {
        case .fixed: return "Always at this time."
        case .afterPrevious: return "Starts when the step before it ends, so it moves if that one changes."
        case .firstAfter: return "Picks the first time on the timetable you can make. With no times saved yet, it shows an estimate (~)."
        case .lastBefore: return "Picks the latest time on the timetable that still leaves by this time, like a morning train that gets you to work on time."
        }
    }
}

// MARK: - Timetable editor

struct TimetableEditorView: View {
    let onSave: (Timetable) -> Void
    @State private var table: Timetable
    @AppStorage private var raw: String

    init(timetable: Timetable, onSave: @escaping (Timetable) -> Void) {
        self.onSave = onSave
        _table = State(initialValue: timetable)
        _raw = AppStorage(wrappedValue: "", Timetables.timesKey(timetable.id))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $table.name)
                Picker("Live data", selection: $table.live) {
                    ForEach(Timetable.Live.allCases, id: \.self) { live in Text(live.title).tag(live) }
                }
            } footer: {
                Text("Live data needs a 511 key and your station (Commute settings). It shows delays for this line on the Commute screen.")
            }
            TrainTimesSection(title: "Departure times",
                              footer: "Swipe left to remove one. Add the ones you actually take.",
                              raw: $raw,
                              suggested: ClockTime(17, 0))
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            onSave(table)
            Pref.bump()
        }
    }
}

// MARK: - Change one step for one day

struct StepDayEdit: Identifiable {
    let block: TimelineBlock
    let day: Date
    var id: String { block.id + DayKey.of(day) }
}

struct StepDayEditor: View {
    @Environment(\.dismiss) private var dismiss
    let edit: StepDayEdit
    @State private var time: Date
    @State private var showRoutine = false

    init(edit: StepDayEdit) {
        self.edit = edit
        _time = State(initialValue: edit.block.start)
    }

    private var dayKey: String { DayKey.of(edit.day) }
    private var hasOverride: Bool { Routines.overrides(for: dayKey)[edit.block.id] != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Button("Save for " + dayLabel) {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                        Routines.setOverride(StepOverride(time: minutes), step: edit.block.id, dayKey: dayKey)
                        Pref.bump()
                        dismiss()
                    }
                } header: {
                    Text(edit.block.title)
                } footer: {
                    Text("Later steps that follow this one (like \"next train after\") move with it.")
                }

                Section {
                    Button("Skip it " + dayLabel, role: .destructive) {
                        Routines.setOverride(StepOverride(skipped: true), step: edit.block.id, dayKey: dayKey)
                        Pref.bump()
                        dismiss()
                    }
                    if hasOverride {
                        Button("Back to the usual") {
                            Routines.setOverride(nil, step: edit.block.id, dayKey: dayKey)
                            Pref.bump()
                            dismiss()
                        }
                    }
                }

                if let type = edit.block.routineType {
                    Section {
                        NavigationLink("Change the \(type.title) routine") {
                            RoutineEditorView(type: type)
                        }
                    } footer: {
                        Text("For changes every time, not just " + dayLabel + ".")
                    }
                }
            }
            .navigationTitle("Change " + dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var dayLabel: String {
        Calendar.current.isDateInToday(edit.day) ? "today" : edit.day.formatted(.dateTime.weekday(.wide))
    }
}
