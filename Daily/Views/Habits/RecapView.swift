import SwiftUI
import SwiftData

/// The numbers behind the Sunday recap.
struct WeekRecap {
    var days: [Date]
    var scores: [DayScore]
    var closedDays: Int
    var bestDay: (day: Date, score: Int)?
    var homeMeals: Int
    var outMeals: Int
    var place: (name: String, score: Double?, visits: Int)?
    var photos: [Data]
    var workouts: Int
    var calories: Int
    var volume: Double
    var bestLift: (exercise: String, weight: Double, reps: Int)?
    var focusMinutes: Int
    var focusRounds: Int
    var checkIns: Int
    var averageWater: Int

    var start: Date { days.first ?? Date() }

    /// "Sep 28 – Oct 4"
    var rangeText: String {
        let from = start.formatted(.dateTime.month(.abbreviated).day())
        let to = end.formatted(.dateTime.month(.abbreviated).day())
        return from + " – " + to
    }
    var end: Date { days.last ?? Date() }

    /// The seven days ending on the most recent Sunday (today, if it's Sunday).
    static func period(endingNear today: Date, calendar cal: Calendar = .current) -> [Date] {
        var end = cal.startOfDay(for: today)
        while cal.component(.weekday, from: end) != 1 {
            guard let prev = cal.date(byAdding: .day, value: -1, to: end) else { break }
            end = prev
        }
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: end) }
    }

    /// Goals for next week, nudged a little past this week.
    func goalOptions(waterGoal: Int, eatOutGoal: Int) -> [(goal: WeekGoal, title: String, detail: String)] {
        [
            (.eatOutLess, "Eat out \(max(min(outMeals - 1, eatOutGoal), 0))× or less", "You ate out \(outMeals)× this week"),
            (.moreWorkouts, "\(workouts + 1) workouts", workouts == 1 ? "You did 1 this week" : "You did \(workouts) this week"),
            (.water, "\(waterGoal) oz of water, 5 days", "You averaged \(averageWater) oz"),
            (.closeDays, "Close \(min(closedDays + 1, 7)) days", "You closed \(closedDays) this week")
        ]
    }
}

extension ScoreBuilder {
    func recap(endingNear today: Date = Date(), restaurants: [Restaurant], focus: [FocusSession],
               allSets: [SetLog]) -> WeekRecap {
        let cal = Calendar.current
        let days = WeekRecap.period(endingNear: today)
        let first = days.first ?? today
        let last = cal.date(byAdding: .day, value: 1, to: days.last ?? today) ?? today
        let inWeek = { (d: Date) in d >= first && d < last }

        let scores = days.map { score(for: $0) }
        let best = zip(days, scores).max { $0.1.score < $1.1.score }
        let meals = food.filter { inWeek($0.date) }
        let out = meals.filter { $0.source == .out }
        let workouts = sessions.filter { $0.finishedAt != nil && inWeek($0.date) }

        // Place of the week: where you went most, then your best-scored.
        let scoresByPlace = RestaurantRanking.scores(restaurants)
        var visitCounts: [UUID: Int] = [:]
        for m in out { if let id = m.restaurantID { visitCounts[id, default: 0] += 1 } }
        let placeID = visitCounts.max { a, b in
            a.value != b.value ? a.value < b.value : (scoresByPlace[a.key] ?? 0) < (scoresByPlace[b.key] ?? 0)
        }?.key
        let place = placeID.flatMap { id in restaurants.first { $0.id == id } }
            .map { (name: $0.name, score: scoresByPlace[$0.id], visits: visitCounts[$0.id] ?? 0) }

        var bestLift: (exercise: String, weight: Double, reps: Int)?
        for s in workouts {
            for b in Coach.newBests(in: s, allSets: allSets) where b.weight > (bestLift?.weight ?? 0) {
                bestLift = b
            }
        }

        let weekFocus = focus.filter { inWeek($0.start) }
        let photos = (journal.filter { inWeek($0.date) }.compactMap(\.photo)
                      + meals.compactMap(\.photo)).prefix(3)
        let waterTotal = water.filter { inWeek($0.date) }.reduce(0) { $0 + $1.ounces }

        return WeekRecap(days: days, scores: scores,
                         closedDays: scores.filter(\.isClosed).count,
                         bestDay: best.map { (day: $0.0, score: $0.1.score) },
                         homeMeals: meals.filter { $0.source.isHome }.count,
                         outMeals: out.count,
                         place: place,
                         photos: Array(photos),
                         workouts: workouts.count,
                         calories: workouts.reduce(0) { $0 + Burn.calories(for: $1) },
                         volume: workouts.reduce(0) { $0 + Coach.volume($1.allSets) },
                         bestLift: bestLift,
                         focusMinutes: weekFocus.reduce(0) { $0 + $1.seconds } / 60,
                         focusRounds: weekFocus.filter(\.completed).count,
                         checkIns: journal.filter { inWeek($0.date) }.count,
                         averageWater: waterTotal / 7)
    }
}

/// Swipeable Sunday recap: the week, food, gym and more, then a goal for next week.
struct RecapView: View {
    @Environment(\.dismiss) private var dismiss
    let recap: WeekRecap

    @State private var page = 0
    @State private var showPlanner = false
    @State private var shareImage: Image?
    @AppStorage(WeekGoal.key) private var goalText = ""

    private let pageCount = 4

    init(recap: WeekRecap) {
        self.recap = recap
    }

    var body: some View {
        ZStack(alignment: .top) {
            background.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: page)
            TabView(selection: $page) {
                weekSlide.tag(0)
                foodSlide.tag(1)
                gymSlide.tag(2)
                nextSlide.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            header
        }
        .sensoryFeedback(.selection, trigger: page)
        .sheet(isPresented: $showPlanner) {
            WeekPlanView(startOnNextWeek: true)
        }
        .task { renderShareImage() }
    }

    private var background: Color {
        switch page {
        case 0: return Palette.ink
        case 1: return Palette.foodText
        case 2: return Palette.gymText
        default: return Palette.bg
        }
    }

    private var foreground: Color {
        switch page {
        case 0: return Palette.bg
        case 1, 2: return Palette.onAccent
        default: return Palette.ink
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(foreground.opacity(i <= page ? 1 : 0.3))
                        .frame(height: 3)
                }
            }
            HStack {
                Text("Your week · " + recap.rangeText)
                    .font(.footnote.weight(.bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                }
                .accessibilityLabel("Close")
            }
            .foregroundStyle(foreground.opacity(0.9))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func slide<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 20)
        .padding(.top, 80)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { page = min(page + 1, pageCount - 1) }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.subheadline.weight(.bold))
            .opacity(0.7)
    }

    // MARK: Slides

    private var weekSlide: some View {
        slide {
            eyebrow("This week you closed")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(recap.closedDays)").font(.system(size: 96, weight: .heavy))
                Text("of 7 days").font(.system(size: 28, weight: .heavy))
            }
            if let best = recap.bestDay {
                Text("\(best.day.formatted(.dateTime.weekday(.wide))) was your best day: \(best.score).")
                    .font(.title3)
                    .opacity(0.85)
            }
            Spacer()
            HStack {
                ForEach(Array(zip(recap.days, recap.scores).enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 6) {
                        ScoreRings(score: pair.1, size: 40)
                        Text(pair.0.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.weight(.bold))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Tap to keep going").font(.footnote).opacity(0.6).frame(maxWidth: .infinity)
        }
    }

    private var foodSlide: some View {
        slide {
            eyebrow("Food")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(recap.homeMeals)").font(.system(size: 72, weight: .heavy))
                Text("meals at home").font(.system(size: 24, weight: .heavy))
            }
            GeometryReader { geo in
                let total = max(recap.homeMeals + recap.outMeals, 1)
                HStack(spacing: 3) {
                    Rectangle().fill(foreground.opacity(0.9))
                        .frame(width: geo.size.width * CGFloat(recap.homeMeals) / CGFloat(total))
                    Rectangle().fill(foreground.opacity(0.35))
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            Text(recap.outMeals == 0 ? "No meals out. Every meal from your own kitchen."
                 : "\(recap.outMeals) meal\(recap.outMeals == 1 ? "" : "s") out (goal: \(MySchedule.eatOutGoalPerWeek) or fewer).")
                .font(.headline)
                .opacity(0.85)
            Spacer()
            if let place = recap.place {
                VStack(alignment: .leading, spacing: 10) {
                    eyebrow("Place of the week")
                    HStack(spacing: 12) {
                        if let score = place.score {
                            Text(String(format: "%.1f", score))
                                .font(.headline.weight(.heavy))
                                .frame(width: 52, height: 52)
                                .overlay(Circle().strokeBorder(foreground, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.title3.weight(.heavy))
                            Text(place.visits == 1 ? "1 visit" : "\(place.visits) visits").font(.subheadline).opacity(0.8)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(foreground.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if !recap.photos.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(recap.photos.enumerated()), id: \.offset) { _, data in
                        PhotoThumbnail(data: data, maxPixel: 300)
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var gymSlide: some View {
        slide {
            eyebrow("Gym")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(recap.workouts)").font(.system(size: 72, weight: .heavy))
                Text(recap.workouts == 1 ? "workout" : "workouts").font(.system(size: 24, weight: .heavy))
            }
            Text("\(recap.calories.formatted()) cal burned · \(Int(recap.volume).formatted()) lb moved")
                .font(.headline)
                .opacity(0.85)
            if let lift = recap.bestLift {
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEW BEST").font(.caption.weight(.heavy)).opacity(0.75)
                        Text("\(lift.exercise) \(Coach.format(lift.weight)) × \(lift.reps)").font(.title3.weight(.heavy))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Spacer()
            VStack(spacing: 10) {
                statLine("Focus", recap.focusRounds > 0
                         ? "\(recap.focusMinutes / 60)h \(recap.focusMinutes % 60)m · \(recap.focusRounds) rounds" : "—")
                statLine("Check-ins", recap.checkIns > 0 ? "\(recap.checkIns)" : "—")
                statLine("Water", "\(recap.averageWater) oz a day")
            }
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.subheadline.weight(.bold))
    }

    private var nextSlide: some View {
        let options = recap.goalOptions(waterGoal: MySchedule.waterGoalOz, eatOutGoal: MySchedule.eatOutGoalPerWeek)
        return VStack(alignment: .leading, spacing: 16) {
            eyebrow("Next week").padding(.top, 80)
            Text(recap.closedDays > 0 ? "Let's beat \(recap.closedDays)." : "Fresh start.")
                .font(.system(size: 34, weight: .heavy))
            Text("Pick one thing to push on. It shows under your rings on Today.")
                .font(.headline)
                .foregroundStyle(Palette.muted)
            ForEach(options, id: \.goal) { option in
                Button {
                    withAnimation(.snappy) { goalText = goalText == option.title ? "" : option.title }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.goal.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.food)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.headline).foregroundStyle(Palette.ink)
                            Text(option.detail).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: goalText == option.title ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(goalText == option.title ? Palette.food : Palette.idle)
                    }
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(goalText == option.title ? Palette.food : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            DetailPrimaryButton(title: "Plan next week's meals", symbol: "sparkles", fill: Palette.food) {
                showPlanner = true
            }
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview("My week", image: shareImage)) {
                    Label("Save my week as an image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// A square card of the week, for saving or sharing.
struct RecapShareCard: View {
    let recap: WeekRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MY WEEK · " + recap.rangeText)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Palette.muted)
            HStack {
                ForEach(Array(zip(recap.days, recap.scores).enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 4) {
                        ScoreRings(score: pair.1, size: 34)
                        Text(pair.0.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 10) {
                shareStat("\(recap.closedDays)/7", "days closed")
                shareStat("\(recap.homeMeals)", "meals at home")
                shareStat("\(recap.workouts)", "workouts")
            }
            if let lift = recap.bestLift {
                Label("New best: \(lift.exercise) \(Coach.format(lift.weight)) × \(lift.reps)", systemImage: "trophy.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.gymText)
            }
            Text("Daily").font(.footnote.weight(.heavy)).foregroundStyle(Palette.faint)
        }
        .padding(22)
        .frame(width: 360)
        .background(Palette.card)
    }

    private func shareStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.heavy)).foregroundStyle(Palette.ink)
            Text(label).font(.caption2).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
