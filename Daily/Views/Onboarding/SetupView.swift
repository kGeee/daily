import SwiftUI

/// First-run setup: your day, how you get to work, extras (gym, an after-work spot) and your week.
/// Also reachable from Settings → "Set up my days again".
struct SetupView: View {
    enum Page: Int, CaseIterable {
        case welcome, day, modes, details, extras, week, review
    }

    var onFinish: () -> Void

    @State private var page: Page = .welcome
    @State private var answers: SetupAnswers
    @State private var forward = true

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        var a = SetupAnswers()
        let d = UserDefaults.standard
        if d.object(forKey: Pref.wake) != nil { a.wake = MySchedule.wake.totalMinutes }
        if d.object(forKey: Pref.workStart) != nil { a.workStart = MySchedule.workStart.totalMinutes }
        if d.object(forKey: Pref.bedtime) != nil { a.bedtime = MySchedule.bedtime.totalMinutes }
        _answers = State(initialValue: a)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .background(Palette.bg.ignoresSafeArea())
        .animation(.snappy(duration: 0.35), value: page)
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if page != .welcome {
                HStack(spacing: 4) {
                    ForEach(1..<Page.allCases.count, id: \.self) { i in
                        Capsule()
                            .fill(i <= page.rawValue ? Palette.commute : Palette.line)
                            .frame(height: 5)
                    }
                }
            } else {
                Spacer()
            }
            Button("Skip") { onFinish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var canContinue: Bool {
        switch page {
        case .modes: return !answers.modes.isEmpty
        case .extras: return !answers.outing || !answers.outingPlace.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if page != .welcome {
                Button {
                    go(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .frame(width: 56, height: 56)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            DetailPrimaryButton(title: nextTitle, fill: Palette.commute) {
                if page == .review {
                    Setup.apply(answers)
                    onFinish()
                } else {
                    go(1)
                }
            }
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.45)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Palette.bg)
    }

    private var nextTitle: String {
        switch page {
        case .welcome: return "Let's go"
        case .review: return "Start my days"
        default: return "Next"
        }
    }

    private func go(_ step: Int) {
        forward = step > 0
        if step > 0 && page == .extras { answers.suggestWeek() }
        if step > 0 && page == .modes { syncExtrasModes() }
        let target = page.rawValue + step
        if let next = Page(rawValue: target) { page = next }
    }

    /// Keep the gym / outing choices pointing at modes you actually picked.
    private func syncExtrasModes() {
        guard let first = answers.modes.first else { return }
        if !answers.modes.contains(answers.gymMode) { answers.gymMode = first }
        if !answers.modes.contains(answers.gymHome) { answers.gymHome = answers.gymMode }
        if !answers.modes.contains(answers.outingMode) { answers.outingMode = first }
        if !answers.modes.contains(answers.outingHome) { answers.outingHome = answers.outingMode }
    }

    // MARK: Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .welcome: welcome
        case .day: dayPage
        case .modes: modesPage
        case .details: detailsPage
        case .extras: extrasPage
        case .week: weekPage
        case .review: reviewPage
        }
    }

    private func title(_ eyebrow: String, _ text: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: eyebrow, color: Palette.commuteText)
            Text(text)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 40)
            HStack(spacing: -10) {
                ForEach(Array(["car.fill", "tram.fill", "bus.fill", "bicycle", "dumbbell.fill"].enumerated()), id: \.offset) { i, symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle([Palette.water, Palette.caltrain, Palette.commute, Palette.food, Palette.gym][i])
                        .frame(width: 56, height: 56)
                        .background(Palette.card, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 3))
                }
            }
            title("Welcome to Daily", "Let's set up your days",
                  "A couple of minutes on how you get to work and what your week looks like. Daily builds your timeline, leave-by times and reminders from it. You can change anything later.")
            VStack(alignment: .leading, spacing: 12) {
                bullet("clock.fill", "When you wake, work and wind down")
                bullet("car.fill", "Drive, shuttle, train, bus, bike or home")
                bullet("dumbbell.fill", "Gym days and regular after-work plans")
                bullet("calendar", "Which kind of day each weekday is")
            }
            .padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.commute)
                .frame(width: 30)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
        }
    }

    private var dayPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Your day", "When does your day run?", "Rough times are fine.")
            DetailCard {
                SetupTimeRow(symbol: "alarm.fill", tint: Palette.sleep, title: "Wake up", minutes: $answers.wake)
                DetailDivider()
                SetupTimeRow(symbol: "briefcase.fill", tint: Palette.work, title: "Start work", minutes: $answers.workStart)
                DetailDivider()
                SetupTimeRow(symbol: "briefcase", tint: Palette.work, title: "Finish work", minutes: $answers.workEnd)
                DetailDivider()
                SetupTimeRow(symbol: "moon.fill", tint: Palette.sleep, title: "Bedtime", minutes: $answers.bedtime)
            }
        }
    }

    private var modesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Getting to work", "How do you get there?",
                  "Pick everything you do on different days. Each one becomes a kind of day you can put on your week.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(CommuteMode.allCases) { mode in
                    modeCard(mode)
                }
            }
        }
    }

    private func modeCard(_ mode: CommuteMode) -> some View {
        let isOn = answers.modes.contains(mode)
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                if isOn { answers.modes.removeAll { $0 == mode } } else { answers.modes.append(mode) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.onAccent : Palette.commute)
                        .frame(width: 42, height: 42)
                        .background(isOn ? Palette.commute : Palette.commuteTint, in: Circle())
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Palette.commute : Palette.idle)
                }
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(mode.blurb)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isOn ? Palette.commute : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    @ViewBuilder
    private var detailsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("The details", "Tell us about each trip",
                  "Used to work out when to leave. Train times can be added later in Commute settings.")
            ForEach(answers.modes) { mode in
                modeDetails(mode)
            }
        }
    }

    private func sectionHeader(_ mode: CommuteMode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.commute)
                .frame(width: 32, height: 32)
                .background(Palette.commuteTint, in: Circle())
            Text(mode.title).font(.headline).foregroundStyle(Palette.ink)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modeDetails(_ mode: CommuteMode) -> some View {
        switch mode {
        case .drive:
            DetailCard {
                sectionHeader(mode)
                SetupMinutesRow(title: "Drive time", minutes: $answers.driveMinutes, range: 5...150)
                DetailDivider()
                SetupMinutesRow(title: "Parking and walking in", minutes: $answers.parkMinutes, range: 0...30, step: 1)
            }
        case .shuttle:
            DetailCard {
                sectionHeader(mode)
                SetupTextRow(title: "Pickup stop", placeholder: "e.g. 4th & King", text: $answers.shuttleStop)
                DetailDivider()
                SetupTimeRow(symbol: "arrow.up.right", tint: Palette.commute, title: "Leaves for work", minutes: $answers.shuttleOut)
                DetailDivider()
                SetupTimeRow(symbol: "arrow.down.left", tint: Palette.commute, title: "Leaves work", minutes: $answers.shuttleHome)
                DetailDivider()
                SetupMinutesRow(title: "Ride", minutes: $answers.shuttleRide, range: 5...150)
                DetailDivider()
                SetupMinutesRow(title: "Walk to the stop", minutes: $answers.walkToStop, range: 0...30, step: 1)
            }
        case .train:
            DetailCard {
                sectionHeader(mode)
                SetupTextRow(title: "Line", placeholder: "Caltrain, BART…", text: $answers.trainLine)
                DetailDivider()
                SetupTextRow(title: "From", placeholder: "e.g. San Francisco", text: $answers.fromStation)
                DetailDivider()
                SetupTextRow(title: "To", placeholder: "e.g. Mountain View", text: $answers.toStation)
                DetailDivider()
                SetupMinutesRow(title: "Ride", minutes: $answers.trainRide, range: 5...150)
                DetailDivider()
                SetupMinutesRow(title: "Walk to your station", minutes: $answers.walkToStation, range: 0...40, step: 1)
                DetailDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("From the station to work")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LastMile.allCases) { option in
                                ChoiceChip(title: option.title, isOn: answers.lastMile == option, tint: Palette.commute) {
                                    answers.lastMile = option
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                if answers.lastMile != .none {
                    DetailDivider()
                    SetupMinutesRow(title: "That takes", minutes: $answers.lastMileMinutes, range: 1...60, step: 1)
                }
            }
        case .bus:
            DetailCard {
                sectionHeader(mode)
                SetupTextRow(title: "Route", placeholder: "e.g. VTA 22", text: $answers.busLine)
                DetailDivider()
                SetupMinutesRow(title: "Ride", minutes: $answers.busRide, range: 5...150)
                DetailDivider()
                SetupMinutesRow(title: "Walk to the stop", minutes: $answers.walkToBus, range: 0...30, step: 1)
            }
        case .bike:
            DetailCard {
                sectionHeader(mode)
                SetupMinutesRow(title: "Door to door", minutes: $answers.bikeMinutes, range: 5...120)
            }
        case .remote:
            DetailCard {
                sectionHeader(mode)
                Text("Nothing to set up: home days just have work on the timeline.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func modeChips(_ selection: Binding<CommuteMode>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(answers.modes) { mode in
                    ChoiceChip(title: mode.title, symbol: mode.symbol, isOn: selection.wrappedValue == mode,
                               tint: Palette.commute) {
                        selection.wrappedValue = mode
                    }
                }
            }
        }
    }

    private func chipRow(_ label: String, _ selection: Binding<CommuteMode>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            modeChips(selection)
        }
        .padding(.vertical, 12)
    }

    private var extrasPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Extras", "Anything else on some days?", "Optional. Each one becomes its own kind of day.")

            DetailCard {
                Toggle(isOn: $answers.gym.animation(.snappy)) {
                    toggleLabel("dumbbell.fill", Palette.gym, "Gym after work", "Leave work early, work out, then head home")
                }
                .tint(Palette.gym)
                .padding(.vertical, 12)
                if answers.gym {
                    DetailDivider()
                    chipRow("Getting to work that day", $answers.gymMode)
                    DetailDivider()
                    SetupTimeRow(symbol: "figure.walk", tint: Palette.gym, title: "Leave work for the gym", minutes: $answers.gymLeave)
                    DetailDivider()
                    SetupMinutesRow(title: "Getting to the gym", minutes: $answers.gymTravel, range: 0...90)
                    DetailDivider()
                    SetupMinutesRow(title: "Workout", minutes: $answers.workoutLength, range: 15...180)
                    DetailDivider()
                    chipRow("Getting home from the gym", $answers.gymHome)
                }
            }

            DetailCard {
                Toggle(isOn: $answers.outing.animation(.snappy)) {
                    toggleLabel("cup.and.saucer.fill", Palette.general, "A regular after-work spot",
                                "Like heading to Mountain View to hang out before going home")
                }
                .tint(Palette.general)
                .padding(.vertical, 12)
                if answers.outing {
                    DetailDivider()
                    SetupTextRow(title: "Where", placeholder: "e.g. Mountain View", text: $answers.outingPlace)
                    DetailDivider()
                    chipRow("Getting to work that day", $answers.outingMode)
                    DetailDivider()
                    SetupMinutesRow(title: "Getting there from work", minutes: $answers.outingTravel, range: 0...90)
                    DetailDivider()
                    SetupMinutesRow(title: "Usually stay", minutes: $answers.outingLength, range: 15...360, step: 15)
                    DetailDivider()
                    chipRow("Getting home from there", $answers.outingHome)
                }
            }
        }
    }

    private func toggleLabel(_ symbol: String, _ tint: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Palette.circle, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(sub).font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }

    private static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private var planTypes: [DayTypeInfo] { Setup.plan(answers).dayTypes }

    private var weekPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Your week", "What's each day usually like?",
                  "You can still switch any single day from Today or the week planner.")
            VStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.weekdayNames[i])
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.ink)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(planTypes) { type in
                                    ChoiceChip(title: type.short, isOn: answers.week[i] == type.id, tint: type.color.color) {
                                        answers.week[i] = type.id
                                    }
                                }
                                ChoiceChip(title: "Off", isOn: answers.week[i] == DayPlanner.off, tint: Palette.muted) {
                                    answers.week[i] = DayPlanner.off
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private var reviewPage: some View {
        let plan = Setup.plan(answers)
        return VStack(alignment: .leading, spacing: 16) {
            title("All set", "Here's your plan",
                  "Times are a first guess. Tap any step on Today to move it, or fine-tune routines in Commute settings.")
            ForEach(plan.dayTypes) { type in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(type.color.color).frame(width: 10, height: 10)
                        Text(type.name).font(.headline).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(daysLabel(for: type.id))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    let resolved = RoutineResolver.resolve(plan.routines[type.id] ?? [], timesFor: { _ in [] })
                    ForEach(resolved, id: \.step.id) { r in
                        HStack(spacing: 10) {
                            Text(ClockTime(minutes: r.start).label)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.muted)
                                .frame(width: 66, alignment: .leading)
                            Image(systemName: r.step.kind.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(r.step.kind.category.color)
                                .frame(width: 18)
                            Text(r.step.title)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(16)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if !plan.timetables.isEmpty {
                Label("Add your usual departure times in Commute settings → Timetables so Daily can pick the right train.",
                      systemImage: "tram.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.commuteText)
                    .padding(14)
                    .background(Palette.commuteTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func daysLabel(for id: String) -> String {
        let short = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let days = answers.week.enumerated().filter { $0.element == id }.map { short[$0.offset] }
        return days.isEmpty ? "Not on your week" : days.joined(separator: ", ")
    }
}

// MARK: - Rows

struct SetupTimeRow: View {
    let symbol: String
    var tint: Color = Palette.commute
    let title: String
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            DatePicker(title, selection: Binding(
                get: { ClockTime(minutes: minutes).on(Date()) },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        .frame(minHeight: 56)
    }
}

struct SetupMinutesRow: View {
    let title: String
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...120
    var step: Int = 5

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            stepButton("minus", enabled: minutes > range.lowerBound) {
                minutes = max(range.lowerBound, minutes - step)
            }
            Text(label)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 62)
                .contentTransition(.numericText())
            stepButton("plus", enabled: minutes < range.upperBound) {
                minutes = min(range.upperBound, minutes + step)
            }
        }
        .frame(minHeight: 56)
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private var label: String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) hr"
            : minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Palette.card2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct SetupTextRow: View {
    let title: String
    var placeholder = ""
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)
        }
        .frame(minHeight: 56)
    }
}
