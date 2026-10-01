import SwiftUI

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
    }
}
