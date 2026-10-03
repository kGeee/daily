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
                PillSegment(Tab.allCases, selection: $tab) { $0.rawValue }

                ZStack(alignment: .top) {
                    if tab == .today {
                        FoodTodaySection()
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        GroceriesSection()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .animation(.snappy(duration: 0.3), value: tab)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
        .sheet(isPresented: $showReview) {
            WeekReviewView()
        }
    }
}

extension MealSlot {
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
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
            summaryCard
            weekCard
            mealsCard
            prepCard
        }
        .animation(.snappy(duration: 0.3), value: todays.count)
        .sensoryFeedback(.success, trigger: todays.count)
        .sheet(item: $draft) { d in
            LogMealSheet(draft: d)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let calories = todays.compactMap { $0.calories }.reduce(0, +)
        let protein = todays.compactMap { $0.protein }.reduce(0, +)
        let carbs = todays.compactMap { $0.carbs }.reduce(0, +)
        let fat = todays.compactMap { $0.fat }.reduce(0, +)
        let goal = max(MySchedule.calorieGoal, 1)
        let progress = Double(calories) / Double(goal)
        let left = goal - calories

        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Palette.idle, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(progress > 1.1 ? Palette.gym : Palette.food,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.5), value: progress)
                VStack(spacing: 0) {
                    Text(calories.formatted())
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("of \(goal.formatted()) cal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 12) {
                macroRow("Protein", grams: protein, goal: MySchedule.proteinGoal, color: Palette.food)
                macroRow("Carbs", grams: carbs, goal: nil, color: Palette.water)
                macroRow("Fat", grams: fat, goal: nil, color: Palette.gym)
                Text(left >= 0 ? "\(left.formatted()) cal left" : "\((-left).formatted()) cal over")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(left >= 0 ? Palette.foodText : Palette.gymText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 18)
    }

    private func macroRow(_ name: String, grams: Int, goal: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                (Text("\(grams)g").font(.subheadline.weight(.heavy)).foregroundStyle(Palette.ink)
                 + Text(goal.map { " / \($0)g" } ?? "").font(.caption).foregroundStyle(Palette.muted))
                    .contentTransition(.numericText())
            }
            if let goal {
                GoalBar(progress: Double(grams) / Double(max(goal, 1)), color: color)
            }
        }
    }

    private var weekCard: some View {
        let home = thisWeek.filter { $0.source.isHome }.count
        let out = thisWeek.count - home
        let total = max(home + out, 1)
        let over = out > MySchedule.eatOutGoalPerWeek

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                SectionLabel(text: "This week")
                (Text("\(home)").font(.headline.weight(.heavy)).foregroundStyle(Palette.food)
                 + Text(" home").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted))
                (Text("\(out)").font(.headline.weight(.heavy)).foregroundStyle(Palette.gym)
                 + Text(" out").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted))
                Spacer()
                Text("goal ≤ \(MySchedule.eatOutGoalPerWeek) out")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(over ? Palette.gymText : Palette.muted)
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
            .frame(height: 8)
        }
        .card(padding: 16)
    }

    // MARK: Meals

    private var mealsCard: some View {
        VStack(spacing: 0) {
            ForEach(MealSlot.allCases) { slot in
                slotSection(slot)
                if slot != MealSlot.allCases.last {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func slotSection(_ slot: MealSlot) -> some View {
        let items = todays.filter { $0.slot == slot }
        let subtotal = items.compactMap { $0.calories }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.food)
                    .frame(width: 32, height: 32)
                    .background(Palette.foodTint, in: Circle())
                Text(slot.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                if subtotal > 0 {
                    Text("\(subtotal) cal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Menu {
                    ForEach(MealSource.allCases) { source in
                        Button(source.title, systemImage: source.isHome ? "house.fill" : "takeoutbag.and.cup.and.straw.fill") {
                            startLog(slot: slot, source: source)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Palette.food, in: Circle())
                }
                .accessibilityLabel("Log \(slot.title)")
            }

            if items.isEmpty {
                if let planned = plan(for: slot) {
                    plannedRow(planned, slot: slot)
                } else {
                    Text("Nothing logged yet")
                        .font(.subheadline)
                        .foregroundStyle(Palette.faint)
                        .padding(.leading, 42)
                }
            }
            ForEach(items) { entry in
                entryRow(entry)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.vertical, 14)
    }

    private func plannedRow(_ planned: MealPlan, slot: MealSlot) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Planned")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.muted)
                Text(planned.isEatingOut ? "Eating out" : planned.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(planned.isEatingOut ? "Log it" : "Ate it") {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(planned.isEatingOut ? Palette.gym : Palette.food, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.leading, 42)
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        Button {
            draft = LogDraft(slot: entry.slot, source: entry.source, name: entry.name, entry: entry)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        sourceTag(entry.source)
                        if let line = macroLine(entry) {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.leading, 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                draft = LogDraft(slot: entry.slot, source: entry.source, name: entry.name, entry: entry)
            }
            Button("Log again", systemImage: "arrow.clockwise") {
                context.insert(FoodEntry(slot: entry.slot, name: entry.name, source: entry.source,
                                         calories: entry.calories, protein: entry.protein,
                                         carbs: entry.carbs, fat: entry.fat))
            }
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(entry) }
        }
    }

    private func macroLine(_ entry: FoodEntry) -> String? {
        var parts: [String] = []
        if let cal = entry.calories { parts.append("\(cal) cal") }
        if let p = entry.protein { parts.append("\(p)g protein") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sourceTag(_ source: MealSource) -> some View {
        Text(source.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(source.isHome ? Palette.foodText : Palette.gymText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(source.isHome ? Palette.foodTint : Palette.gymTint, in: Capsule())
    }

    private func startLog(slot: MealSlot, source: MealSource) {
        let planned = plan(for: slot)
        let name = (planned != nil && planned?.isEatingOut == (source == .out)) ? (planned?.title ?? "") : ""
        draft = LogDraft(slot: slot, source: source, name: name == MealPlan.eatOut ? "" : name)
    }

    private var prepCard: some View {
        let meals = recipes.reduce(0) { $0 + $1.servings }
        return HStack(spacing: 14) {
            Image(systemName: "frying.pan.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.food)
                .frame(width: 44, height: 44)
                .background(Palette.card, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "Next prep block", color: Palette.foodText)
                Text("Sunday · \(MySchedule.prepStart.label) – \(MySchedule.prepEnd.label)")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                Text(recipes.isEmpty
                     ? "Add recipes in Plan & groceries to plan what you'll cook."
                     : "Makes \(meals) meals from \(recipes.count) recipe\(recipes.count == 1 ? "" : "s").")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
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
    @State private var showTime = false
    @FocusState private var nameFocused: Bool

    private let entry: FoodEntry?
    @State private var time: Date

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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

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
        let description = trimmedName
        Task {
            do {
                let result = try await RecipeAI.estimate(meal: description)
                withAnimation(.snappy) {
                    calories = String(Int(result.calories.rounded()))
                    protein = String(Int(result.protein.rounded()))
                    carbs = String(Int(result.carbs.rounded()))
                    fat = String(Int(result.fat.rounded()))
                    estimateNote = result.note
                }
            } catch {
                estimateNote = error.localizedDescription
            }
            estimating = false
        }
    }

    var body: some View {
        DetailSheetLayout {
            DetailHero(background: BlockCategory.food.hero, symbol: source.isHome ? "fork.knife" : "takeoutbag.and.cup.and.straw.fill",
                       iconColor: source.isHome ? Palette.food : Palette.gym,
                       timeText: slot.title + " · " + time.formatted(date: .omitted, time: .shortened),
                       onClose: { dismiss() },
                       trailing: {
                           roundButton("checkmark", label: "Save", action: save)
                               .disabled(trimmedName.isEmpty)
                               .opacity(trimmedName.isEmpty ? 0.5 : 1)
                       }, title: {
                           TextField("", text: $name,
                                     prompt: Text(source == .out ? "Where / what?" : "What did you eat?")
                                        .foregroundStyle(Palette.heroOn.opacity(0.5)),
                                     axis: .vertical)
                               .lineLimit(1...3)
                               .focused($nameFocused)
                       })
        } content: {
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Meal")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MealSlot.allCases) { s in
                                ChoiceChip(title: s.title, symbol: s.symbol, isOn: slot == s, tint: Palette.food) {
                                    slot = s
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                DetailDivider().padding(.leading, -44)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Where from")
                    HStack(spacing: 8) {
                        ForEach(MealSource.allCases) { s in
                            ChoiceChip(title: s.title, isOn: source == s, tint: s.isHome ? Palette.food : Palette.gym) {
                                source = s
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                DetailDivider().padding(.leading, -44)
                DetailExpandableRow(symbol: "clock.fill", tint: Palette.food,
                                    title: time.formatted(date: .abbreviated, time: .shortened),
                                    value: Calendar.current.isDateInToday(time) ? "Today" : nil,
                                    expanded: $showTime) {
                    DatePicker("When", selection: $time)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
            }

            if source != .out && !recipes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "From your recipes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recipes) { recipe in
                                ChoiceChip(title: recipe.name, isOn: name == recipe.name, tint: Palette.food) {
                                    withAnimation(.snappy) { use(recipe) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            nutritionCard

            if let entry {
                DetailDeleteButton(title: "Delete this meal") {
                    context.delete(entry)
                    dismiss()
                }
            } else {
                DetailPrimaryButton(title: "Log " + slot.title.lowercased(), symbol: "plus", fill: Palette.food, action: save)
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.5 : 1)
            }
        }
        .onAppear {
            if entry == nil, calories.isEmpty, let match = recipes.first(where: { $0.name == name }) {
                use(match)
            }
            if entry == nil && name.isEmpty { nameFocused = true }
        }
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Nutrition")
                Spacer()
                Button {
                    estimate()
                } label: {
                    HStack(spacing: 6) {
                        if estimating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(estimating ? "Estimating…" : "Estimate")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.foodText)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Palette.foodTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(estimating || trimmedName.isEmpty)
                .opacity(trimmedName.isEmpty ? 0.5 : 1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                macroField("Calories", unit: "cal", text: $calories)
                macroField("Protein", unit: "g", text: $protein)
                macroField("Carbs", unit: "g", text: $carbs)
                macroField("Fat", unit: "g", text: $fat)
            }
            Text(estimateNote ?? "Describe it specifically for a better estimate, e.g. \"chicken burrito bowl, white rice, black beans, guac\".")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func macroField(_ title: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("—", text: text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
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
            context.insert(FoodEntry(date: time, slot: slot, name: trimmed, source: source,
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
