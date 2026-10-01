import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A time-of-day picker bound to "minutes after midnight".
struct TimeField: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { ClockTime(minutes: minutes).on(Date()) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
    }
}

struct MinutesStepper: View {
    let title: String
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...120
    var step: Int = 5

    var body: some View {
        Stepper(value: $minutes, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(minutes) min").foregroundStyle(Palette.muted)
            }
        }
    }
}

/// A list of train departure times stored as comma-separated minutes.
struct TrainTimesSection: View {
    let title: String
    let footer: String
    @Binding var raw: String
    @State private var newTime: Date

    init(title: String, footer: String, raw: Binding<String>, suggested: ClockTime) {
        self.title = title
        self.footer = footer
        _raw = raw
        _newTime = State(initialValue: suggested.on(Date()))
    }

    private var times: [Int] { Pref.parseTrains(raw) }

    var body: some View {
        Section {
            if times.isEmpty {
                Text("No trains yet")
                    .foregroundStyle(Palette.muted)
            }
            ForEach(times, id: \.self) { minutes in
                Text(ClockTime(minutes: minutes).label)
            }
            .onDelete { offsets in
                var list = times
                list.remove(atOffsets: offsets)
                raw = Pref.joinTrains(list)
            }
            HStack {
                DatePicker("Add a train", selection: $newTime, displayedComponents: .hourAndMinute)
                Button("Add") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                    let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    raw = Pref.joinTrains(times + [minutes])
                    newTime = newTime.addingTimeInterval(20 * 60)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(Pref.calorieGoal) private var calorieGoal = Pref.calorieGoalDefault
    @AppStorage(Pref.proteinGoal) private var proteinGoal = Pref.proteinGoalDefault
    @AppStorage(Pref.liveStationName) private var liveStationName = ""
    @AppStorage(Pref.directionToWork) private var directionToWork = Pref.directionToWorkDefault
    @State private var key511 = Keychain.read(Keychain.fiveOneOne) ?? ""
    @State private var exportURL: URL?
    @State private var backupMessage: String?
    @State private var importing = false
    @State private var pendingRestore: URL?

    @AppStorage(Pref.wake) private var wake = Pref.wakeDefault
    @AppStorage(Pref.workStart) private var workStart = Pref.workStartDefault
    @AppStorage(Pref.lunch) private var lunch = Pref.lunchDefault
    @AppStorage(Pref.dinner) private var dinner = Pref.dinnerDefault
    @AppStorage(Pref.windDown) private var windDown = Pref.windDownDefault
    @AppStorage(Pref.bedtime) private var bedtime = Pref.bedtimeDefault

    @AppStorage(Pref.shuttleStop) private var shuttleStop = ""
    @AppStorage(Pref.shuttleOut) private var shuttleOut = Pref.shuttleOutDefault
    @AppStorage(Pref.shuttleHome) private var shuttleHome = Pref.shuttleHomeDefault
    @AppStorage(Pref.walkToStop) private var walkToStop = Pref.walkToStopDefault

    @AppStorage(Pref.leaveForGym) private var leaveForGym = Pref.leaveForGymDefault
    @AppStorage(Pref.gymTravel) private var gymTravel = Pref.gymTravelDefault
    @AppStorage(Pref.workoutLength) private var workoutLength = Pref.workoutLengthDefault
    @AppStorage(Pref.gymToStation) private var gymToStation = Pref.gymToStationDefault

    @AppStorage(Pref.homeStation) private var homeStation = ""
    @AppStorage(Pref.walkToStation) private var walkToStation = Pref.walkToStationDefault
    @AppStorage(Pref.caltrainRide) private var caltrainRide = Pref.caltrainRideDefault
    @AppStorage(Pref.lastMile) private var lastMile = Pref.lastMileDefault
    @AppStorage(Pref.caltrainLeaveWork) private var caltrainLeaveWork = Pref.caltrainLeaveWorkDefault
    @AppStorage(Pref.morningTrains) private var morningTrains = ""
    @AppStorage(Pref.eveningTrains) private var eveningTrains = ""

    @AppStorage(Pref.prepStart) private var prepStart = Pref.prepStartDefault
    @AppStorage(Pref.prepEnd) private var prepEnd = Pref.prepEndDefault

    @AppStorage(Pref.reminderLead) private var reminderLead = Pref.reminderLeadDefault
    @AppStorage(Pref.waterGoal) private var waterGoal = Pref.waterGoalDefault
    @AppStorage(Pref.eatOutGoal) private var eatOutGoal = Pref.eatOutGoalDefault

    @AppStorage(Pref.revision) private var revision = 0
    @State private var apiKey = Keychain.read() ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Work shuttle") {
                    TextField("Stop name", text: $shuttleStop, prompt: Text(Pref.shuttleStopDefault))
                    TimeField(title: "Morning shuttle", minutes: $shuttleOut)
                    TimeField(title: "Shuttle home", minutes: $shuttleHome)
                    MinutesStepper(title: "Walk to the stop", minutes: $walkToStop, range: 0...45)
                }

                Section {
                    TimeField(title: "Leave work", minutes: $leaveForGym)
                    MinutesStepper(title: "Getting to the gym", minutes: $gymTravel, range: 0...60)
                    MinutesStepper(title: "Workout length", minutes: $workoutLength, range: 15...180)
                    MinutesStepper(title: "Gym → Sunnyvale station", minutes: $gymToStation, range: 0...60)
                } header: {
                    Text("Gym days")
                } footer: {
                    Text("Workout: \(ClockTime(minutes: leaveForGym + gymTravel).label) – \(ClockTime(minutes: leaveForGym + gymTravel + workoutLength).label). The app picks the first evening train you can make after that.")
                }

                Section {
                    TextField("Home station", text: $homeStation, prompt: Text("e.g. San Francisco"))
                    MinutesStepper(title: "Walk to the station", minutes: $walkToStation, range: 0...45)
                    MinutesStepper(title: "Train ride", minutes: $caltrainRide, range: 5...90)
                    MinutesStepper(title: "Sunnyvale ↔ office", minutes: $lastMile, range: 0...45)
                    TimeField(title: "Leave work (Caltrain days)", minutes: $caltrainLeaveWork)
                } header: {
                    Text("Caltrain")
                }

                TrainTimesSection(
                    title: "Morning trains to Sunnyvale",
                    footer: "Departure times from your station. The app picks the latest one that gets you in by \(ClockTime(minutes: workStart).label).",
                    raw: $morningTrains,
                    suggested: ClockTime(7, 0))

                TrainTimesSection(
                    title: "Evening trains from Sunnyvale",
                    footer: "Used for gym days and Caltrain days. Swipe left to remove one.",
                    raw: $eveningTrains,
                    suggested: ClockTime(17, 0))

                Section {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, newValue in
                            Keychain.save(newValue)
                        }
                    if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                        Link("Get a key", destination: url)
                    }
                } header: {
                    Text("AI (optional)")
                } footer: {
                    Text("Used to import recipes from Instagram, estimate calories and macros, and read recipe text. Stored in your iPhone's Keychain and sent only to Anthropic. Usage is billed to your Anthropic account.")
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
                    Text("Shows live departures and delays on the Commute screen. Your saved train times above are still used for planning.")
                }

                Section {
                    Button("Create backup file") {
                        do {
                            exportURL = try Backup.export(context: context)
                            backupMessage = nil
                        } catch {
                            backupMessage = error.localizedDescription
                        }
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Save or send the backup", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Restore from a backup…") { importing = true }
                    if let backupMessage {
                        Text(backupMessage).font(.footnote).foregroundStyle(Palette.muted)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Save the file to iCloud Drive or Files every so often. Restoring replaces everything in the app with the backup.")
                }

                Section("Your day") {
                    TimeField(title: "Wake up", minutes: $wake)
                    TimeField(title: "Start work", minutes: $workStart)
                    TimeField(title: "Lunch", minutes: $lunch)
                    TimeField(title: "Dinner", minutes: $dinner)
                    TimeField(title: "Wind down", minutes: $windDown)
                    TimeField(title: "Bedtime", minutes: $bedtime)
                }

                Section("Sunday meal prep") {
                    TimeField(title: "Start", minutes: $prepStart)
                    TimeField(title: "End", minutes: $prepEnd)
                }

                Section("Goals & reminders") {
                    MinutesStepper(title: "Remind me before leaving", minutes: $reminderLead, range: 0...60)
                    Stepper(value: $waterGoal, in: 32...200, step: 8) {
                        HStack {
                            Text("Water goal")
                            Spacer()
                            Text("\(waterGoal) oz").foregroundStyle(Palette.muted)
                        }
                    }
                    Stepper(value: $calorieGoal, in: 1200...4500, step: 50) {
                        HStack {
                            Text("Calories a day")
                            Spacer()
                            Text(calorieGoal.formatted()).foregroundStyle(Palette.muted)
                        }
                    }
                    Stepper(value: $proteinGoal, in: 40...300, step: 5) {
                        HStack {
                            Text("Protein a day")
                            Spacer()
                            Text("\(proteinGoal) g").foregroundStyle(Palette.muted)
                        }
                    }
                    Stepper(value: $eatOutGoal, in: 0...14) {
                        HStack {
                            Text("Eat out at most")
                            Spacer()
                            Text("\(eatOutGoal)× / week").foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear { revision += 1 }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { pendingRestore = url }
        }
        .confirmationDialog("Replace everything with this backup?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Replace all data", role: .destructive) {
                guard let url = pendingRestore else { return }
                do {
                    let count = try Backup.restore(from: url, context: context)
                    backupMessage = "Restored (\(count) meals, recipes, workouts and events)."
                } catch {
                    backupMessage = "Couldn't restore: " + error.localizedDescription
                }
                pendingRestore = nil
            }
        }
    }
}

struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Pref.liveStationName) private var liveStationName = ""
    @AppStorage(Pref.liveHomeStops) private var liveHomeStops = ""
    @AppStorage(Pref.liveSunnyvaleStops) private var liveSunnyvaleStops = ""
    @State private var stations: [Caltrain511.Station] = []
    @State private var errorText: String?
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("Loading stations…").foregroundStyle(Palette.muted) }
            }
            if let errorText {
                Text(errorText).foregroundStyle(Palette.gymText)
            }
            ForEach(stations) { station in
                Button {
                    liveStationName = station.name
                    liveHomeStops = station.stopIDs.joined(separator: ",")
                    if let sunnyvale = stations.first(where: { $0.name.localizedCaseInsensitiveContains("Sunnyvale") }) {
                        liveSunnyvaleStops = sunnyvale.stopIDs.joined(separator: ",")
                    }
                    dismiss()
                } label: {
                    HStack {
                        Text(station.name).foregroundStyle(Palette.ink)
                        Spacer()
                        if station.name == liveStationName {
                            Image(systemName: "checkmark").foregroundStyle(Palette.commute)
                        }
                    }
                }
            }
        }
        .navigationTitle("Home station")
        .task {
            do {
                stations = try await Caltrain511.stations()
            } catch {
                errorText = error.localizedDescription
            }
            loading = false
        }
    }
}
