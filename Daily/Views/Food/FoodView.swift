import SwiftUI
import SwiftData

struct FoodView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today = "Today"
        case plan = "Plan & groceries"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .today
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeader(eyebrow: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                 title: "Food")
                    Spacer()
                    Button {
                        showReview = true
                    } label: {
                        Label("Review", systemImage: "chart.bar.xaxis")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.foodText)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Palette.foodTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .today: FoodTodaySection()
                case .plan: GroceriesSection()
                }
            }
            .padding(16)
        }
        .background(Palette.bg.ignoresSafeArea())
        .sheet(isPresented: $showReview) {
            WeekReviewView()
        }
    }
}

// MARK: - Today

struct LogDraft: Identifiable {
    let id = UUID()
    var slot: MealSlot
    var source: MealSource
    var name: String = ""
    /// Set when editing something already logged.
    var entry: FoodEntry? = nil
}

struct FoodTodaySection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var plans: [MealPlan]
    @State private var draft: LogDraft?

    private func plan(for slot: MealSlot) -> MealPlan? {
        let key = DayKey.of(Date())
        return plans.first { $0.dayKey == key && $0.slot == slot }
    }

    private var todays: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var thisWeek: [FoodEntry] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return entries.filter { week.contains($0.date) }
    }

    var body: some View {
        VStack(spacing: 14) {
            weekCard
            mealsCard
            prepCard
        }
        .sheet(item: $draft) { d in
            LogMealSheet(draft: d)
        }
    }

    private var weekCard: some View {
        let home = thisWeek.filter { $0.source.isHome }.count
        let out = thisWeek.count - home
        let total = max(home + out, 1)
        let calories = todays.compactMap { $0.calories }.reduce(0, +)
        let protein = todays.compactMap { $0.protein }.reduce(0, +)
        let carbs = todays.compactMap { $0.carbs }.reduce(0, +)
        let fat = todays.compactMap { $0.fat }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "This week")
                Spacer()
                Text("goal: eat out \(MySchedule.eatOutGoalPerWeek)× or less")
                    .font(.caption)
                    .foregroundStyle(out > MySchedule.eatOutGoalPerWeek ? Palette.gymText : Palette.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                (Text("\(home)").font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.food)
                 + Text(" home").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted))
                (Text("\(out)").font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.gym)
                 + Text(" out").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted))
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    if home + out == 0 {
                        Capsule().fill(Palette.idle)
                    } else {
                        Rectangle().fill(Palette.food)
                            .frame(width: max(0, (geo.size.width - 3) * CGFloat(home) / CGFloat(total)))
                        Rectangle().fill(Palette.gym)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)

            SectionLabel(text: "Today")
                .padding(.top, 4)
            HStack(spacing: 8) {
                miniStat(label: "Calories", value: "\(calories > 0 ? calories.formatted() : "0")/\(MySchedule.calorieGoal.formatted())",
                         progress: Double(calories) / Double(max(MySchedule.calorieGoal, 1)))
                miniStat(label: "Protein", value: "\(protein)/\(MySchedule.proteinGoal)g",
                         progress: Double(protein) / Double(max(MySchedule.proteinGoal, 1)))
                miniStat(label: "Carbs", value: carbs > 0 ? "\(carbs)g" : "—")
                miniStat(label: "Fat", value: fat > 0 ? "\(fat)g" : "—")
            }
        }
        .card()
    }

    private func miniStat(label: String, value: String, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress {
                GoalBar(progress: progress, color: Palette.food)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mealsCard: some View {
        VStack(spacing: 0) {
            ForEach(MealSlot.allCases) { slot in
                let items = todays.filter { $0.slot == slot }
                HStack(alignment: .top, spacing: 12) {
                    SectionLabel(text: slot.title)
                        .frame(width: 84, alignment: .leading)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        if items.isEmpty {
                            if let planned = plan(for: slot) {
                                HStack(spacing: 8) {
                                    Text("Planned: " + planned.title)
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.muted)
                                    Spacer(minLength: 4)
                                    Button(planned.isEatingOut ? "Ate out" : "Ate it") {
                                        if planned.isEatingOut {
                                            draft = LogDraft(slot: slot, source: .out)
                                        } else {
                                            let recipe = recipes.first { $0.name == planned.title }
                                            context.insert(FoodEntry(slot: slot, name: planned.title, source: .prepped,
                                                                     calories: recipe?.caloriesPerServing,
                                                                     protein: recipe?.proteinPerServing,
                                                                     carbs: recipe?.carbsPerServing,
                                                                     fat: recipe?.fatPerServing))
                                        }
                                    }
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(Palette.onAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(planned.isEatingOut ? Palette.gym : Palette.food, in: Capsule())
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text("Not logged")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                        ForEach(items) { entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Palette.ink)
                                    if let cal = entry.calories {
                                        Text("\(cal) cal" + (entry.protein.map { " · \($0)g protein" } ?? ""))
                                            .font(.caption)
                                            .foregroundStyle(Palette.muted)
                                    }
                                }
                                Spacer(minLength: 4)
                                sourceTag(entry.source)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                draft = LogDraft(slot: entry.slot, source: entry.source, name: entry.name, entry: entry)
                            }
                            .contextMenu {
                                Button("Edit") {
                                    draft = LogDraft(slot: entry.slot, source: entry.source, name: entry.name, entry: entry)
                                }
                                Button("Delete", role: .destructive) { context.delete(entry) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(MealSource.allCases) { source in
                            Button(source.title) {
                                let planned = plan(for: slot)
                                let name = (planned != nil && planned?.isEatingOut == (source == .out)) ? (planned?.title ?? "") : ""
                                draft = LogDraft(slot: slot, source: source, name: name == MealPlan.eatOut ? "" : name)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.food)
                            .frame(width: 44, height: 32)
                    }
                    .accessibilityLabel("Log \(slot.title)")
                }
                .padding(.vertical, 12)
                if slot != MealSlot.allCases.last {
                    Divider().overlay(Palette.line)
                }
            }
        }
        .card(padding: 16)
    }

    private func sourceTag(_ source: MealSource) -> some View {
        Text(source.title.uppercased())
            .font(.caption2.weight(.heavy))
            .foregroundStyle(source.isHome ? Palette.foodText : Palette.gymText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(source.isHome ? Palette.foodTint : Palette.gymTint,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var prepCard: some View {
        let meals = recipes.reduce(0) { $0 + $1.servings }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Next prep block", color: Palette.foodText)
            Text("Sunday · \(MySchedule.prepStart.label) – \(MySchedule.prepEnd.label)")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Palette.ink)
            Text(recipes.isEmpty
                 ? "Add recipes in Plan & groceries to plan what you'll cook."
                 : "Makes \(meals) meals from \(recipes.count) recipe\(recipes.count == 1 ? "" : "s"). It's on your Sunday timeline.")
                .font(.footnote)
                .foregroundStyle(Palette.ink)
        }
        .card(fill: Palette.foodTint)
    }
}

struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]

    @State private var name = ""
    @State private var slot: MealSlot
    @State private var source: MealSource
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var estimating = false
    @State private var estimateNote: String?

    private let entry: FoodEntry?
    @State private var time: Date
    @State private var confirmDelete = false

    init(draft: LogDraft) {
        entry = draft.entry
        _name = State(initialValue: draft.name)
        _slot = State(initialValue: draft.slot)
        _source = State(initialValue: draft.source)
        _time = State(initialValue: draft.entry?.date ?? Date())
        if let e = draft.entry {
            _calories = State(initialValue: e.calories.map(String.init) ?? "")
            _protein = State(initialValue: e.protein.map(String.init) ?? "")
            _carbs = State(initialValue: e.carbs.map(String.init) ?? "")
            _fat = State(initialValue: e.fat.map(String.init) ?? "")
        }
    }

    private func use(_ recipe: Recipe) {
        name = recipe.name
        calories = recipe.caloriesPerServing.map(String.init) ?? ""
        protein = recipe.proteinPerServing.map(String.init) ?? ""
        carbs = recipe.carbsPerServing.map(String.init) ?? ""
        fat = recipe.fatPerServing.map(String.init) ?? ""
    }

    private func estimate() {
        estimating = true
        estimateNote = nil
        let description = name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let result = try await RecipeAI.estimate(meal: description)
                calories = String(Int(result.calories.rounded()))
                protein = String(Int(result.protein.rounded()))
                carbs = String(Int(result.carbs.rounded()))
                fat = String(Int(result.fat.rounded()))
                estimateNote = result.note
            } catch {
                estimateNote = error.localizedDescription
            }
            estimating = false
        }
    }

    private func numberRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(source == .out ? "Where / what did you get?" : "What did you eat?", text: $name)
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { s in Text(s.title).tag(s) }
                    }
                    Picker("Source", selection: $source) {
                        ForEach(MealSource.allCases) { s in Text(s.title).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    if entry != nil {
                        DatePicker("When", selection: $time)
                    }
                }
                if source != .out && !recipes.isEmpty {
                    Section("From your recipes") {
                        ForEach(recipes) { recipe in
                            Button {
                                use(recipe)
                            } label: {
                                HStack {
                                    Text(recipe.name).foregroundStyle(Palette.ink)
                                    Spacer()
                                    if let line = recipe.macroLine {
                                        Text(line).font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    numberRow("Calories", text: $calories)
                    numberRow("Protein (g)", text: $protein)
                    numberRow("Carbs (g)", text: $carbs)
                    numberRow("Fat (g)", text: $fat)
                    Button {
                        estimate()
                    } label: {
                        HStack {
                            Text(estimating ? "Estimating…" : "Estimate from the description")
                            Spacer()
                            if estimating { ProgressView() }
                        }
                    }
                    .disabled(estimating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let estimateNote {
                        Text(estimateNote).font(.footnote).foregroundStyle(Palette.muted)
                    }
                } header: {
                    Text("Nutrition (optional)")
                } footer: {
                    Text("Be specific for better estimates, e.g. \"Chipotle chicken bowl, white rice, black beans, guac\".")
                }
                if let entry {
                    Section {
                        Button("Delete this meal", role: .destructive) {
                            context.delete(entry)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Log meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if entry == nil, calories.isEmpty, let match = recipes.first(where: { $0.name == name }) {
                use(match)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let entry {
            entry.name = trimmed
            entry.slotRaw = slot.rawValue
            entry.sourceRaw = source.rawValue
            entry.date = time
            entry.calories = Int(calories)
            entry.protein = Int(protein)
            entry.carbs = Int(carbs)
            entry.fat = Int(fat)
        } else {
            context.insert(FoodEntry(slot: slot, name: trimmed, source: source,
                                     calories: Int(calories), protein: Int(protein),
                                     carbs: Int(carbs), fat: Int(fat)))
        }
        dismiss()
    }
}

struct GoalBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.idle)
                Capsule().fill(progress > 1.1 ? Palette.gym : color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
