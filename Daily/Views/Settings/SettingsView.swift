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
    @State private var exportURL: URL?
    @AppStorage(Burn.weightKey) private var bodyWeight: Double = 0
    @AppStorage("pref.restSeconds") private var restSeconds = 90
    @AppStorage(CheckIn.onKey) private var checkInOn = false
    @AppStorage(CheckIn.timeKey) private var checkInTime = CheckIn.defaultTime
    @State private var showSetup = false
    @State private var backupMessage: String?
    @State private var importing = false
    @State private var pendingRestore: URL?

    @AppStorage(Pref.wake) private var wake = Pref.wakeDefault
    @AppStorage(Pref.workStart) private var workStart = Pref.workStartDefault
    @AppStorage(Pref.lunch) private var lunch = Pref.lunchDefault
    @AppStorage(Pref.dinner) private var dinner = Pref.dinnerDefault
    @AppStorage(Pref.windDown) private var windDown = Pref.windDownDefault
    @AppStorage(Pref.bedtime) private var bedtime = Pref.bedtimeDefault

    @AppStorage(Pref.prepStart) private var prepStart = Pref.prepStartDefault
    @AppStorage(Pref.prepEnd) private var prepEnd = Pref.prepEndDefault

    @AppStorage(Pref.waterGoal) private var waterGoal = Pref.waterGoalDefault
    @AppStorage(Pref.eatOutGoal) private var eatOutGoal = Pref.eatOutGoalDefault

    @AppStorage(Pref.revision) private var revision = 0
    @State private var apiKey = Keychain.read() ?? ""
    @State private var yelpKey = Keychain.read(PlaceSearch.yelpAccount) ?? ""
    @State private var googleKey = Keychain.read(PlaceSearch.googleAccount) ?? ""
    @AppStorage(MapsApp.prefKey) private var mapsApp = MapsApp.apple.rawValue
    @AppStorage(MapsApp.searchKey) private var placeSearch = MapsApp.apple.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Your day") {
                    TimeField(title: "Wake up", minutes: $wake)
                    TimeField(title: "Start work", minutes: $workStart)
                    TimeField(title: "Lunch", minutes: $lunch)
                    TimeField(title: "Dinner", minutes: $dinner)
                    TimeField(title: "Wind down", minutes: $windDown)
                    TimeField(title: "Bedtime", minutes: $bedtime)
                }

                Section {
                    NavigationLink {
                        CommuteSettingsView(embedded: true)
                    } label: {
                        Label("Commute, trains and reminders", systemImage: "tram.fill")
                    }
                    Button {
                        showSetup = true
                    } label: {
                        Label("Set up my days again", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("Your routines for each kind of day, timetables, live Caltrain and departure reminders.")
                }

                Section {
                    Toggle("Midday check-in reminder", isOn: Binding(
                        get: { checkInOn },
                        set: { on in
                            if on {
                                Task {
                                    checkInOn = await Reminders.requestPermission()
                                    await CheckIn.updateReminder()
                                }
                            } else {
                                checkInOn = false
                                Task { await CheckIn.updateReminder() }
                            }
                        }
                    ))
                    if checkInOn {
                        TimeField(title: "Remind me at", minutes: $checkInTime)
                            .onChange(of: checkInTime) { _, _ in Task { await CheckIn.updateReminder() } }
                    }
                } header: {
                    Text("Photo journal")
                } footer: {
                    Text("A daily nudge to snap a photo of how the day is going. The check-in card also shows on Today around then.")
                }

                Section("Sunday meal prep") {
                    TimeField(title: "Start", minutes: $prepStart)
                    TimeField(title: "End", minutes: $prepEnd)
                }

                Section("Goals") {
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
                    HStack {
                        Text("Body weight")
                        Spacer()
                        TextField("lb", value: $bodyWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("lb").foregroundStyle(Palette.muted)
                    }
                    Stepper(value: $restSeconds, in: 30...300, step: 15) {
                        HStack {
                            Text("Rest between sets")
                            Spacer()
                            Text("\(restSeconds)s").foregroundStyle(Palette.muted)
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
                    Text("Used to import recipes from Instagram, estimate calories and macros, and plan meal prep. Stored in your iPhone's Keychain and sent only to Anthropic. Usage is billed to your Anthropic account.")
                }

                Section {
                    Picker("Open places in", selection: $mapsApp) {
                        ForEach(MapsApp.allCases) { app in Text(app.title).tag(app.rawValue) }
                    }
                    Picker("Search with", selection: $placeSearch) {
                        Text("Apple Maps").tag(MapsApp.apple.rawValue)
                        Text("Google").tag(MapsApp.google.rawValue)
                    }
                    SecureField("Google Places API key", text: $googleKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: googleKey) { _, newValue in
                            Keychain.save(newValue, account: PlaceSearch.googleAccount)
                        }
                    SecureField("Yelp API key", text: $yelpKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: yelpKey) { _, newValue in
                            Keychain.save(newValue, account: PlaceSearch.yelpAccount)
                        }
                    if let url = URL(string: "https://www.yelp.com/developers/v3/manage_app") {
                        Link("Get a Yelp key", destination: url)
                    }
                    if let url = URL(string: "https://developers.google.com/maps/documentation/places/web-service/get-api-key") {
                        Link("Get a Google Places key", destination: url)
                    }
                } header: {
                    Text("Maps & restaurant ratings")
                } footer: {
                    Text("Addresses open in the maps app you pick (Google Maps opens in its app if installed, otherwise the web). Search uses Apple Maps for free. Google search adds Google star ratings and needs a Places API (New) key; Google bills searches beyond its free monthly allowance. A Yelp key adds Yelp stars and review counts; Yelp's API is paid after a trial.")
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showSetup) {
            SetupView { showSetup = false }
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
                    if let mountainView = stations.first(where: { $0.name.localizedCaseInsensitiveContains("Mountain View") }) {
                        UserDefaults.standard.set(mountainView.stopIDs.joined(separator: ","), forKey: Pref.liveMountainViewStops)
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
