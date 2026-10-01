import SwiftUI
import SwiftData

struct FoodView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today = "Today"
        case plan = "Plan & groceries"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(eyebrow: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                             title: "Food")
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
    }
}

// MARK: - Today

struct LogDraft: Identifiable {
    let id = UUID()
    var slot: MealSlot
    var source: MealSource
    var name: String = ""
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

            HStack(spacing: 8) {
                miniStat(label: "Calories today", value: calories > 0 ? calories.formatted() : "—")
                miniStat(label: "Protein today", value: protein > 0 ? "\(protein) g" : "—")
            }
            .padding(.top, 4)
        }
        .card()
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: label)
            Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(Palette.ink)
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
                                        context.insert(FoodEntry(slot: slot, name: planned.title,
                                                                 source: planned.isEatingOut ? .out : .prepped))
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
                                Text(entry.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 4)
                                sourceTag(entry.source)
                            }
                            .contextMenu {
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

    init(draft: LogDraft) {
        _name = State(initialValue: draft.name)
        _slot = State(initialValue: draft.slot)
        _source = State(initialValue: draft.source)
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
                }
                if source == .prepped && !recipes.isEmpty {
                    Section("From your prep") {
                        ForEach(recipes) { recipe in
                            Button(recipe.name) { name = recipe.name }
                        }
                    }
                }
                Section("Optional") {
                    TextField("Calories", text: $calories).keyboardType(.numberPad)
                    TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Log meal")
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
    }

    private func save() {
        context.insert(FoodEntry(slot: slot,
                                 name: name.trimmingCharacters(in: .whitespaces),
                                 source: source,
                                 calories: Int(calories),
                                 protein: Int(protein)))
        dismiss()
    }
}
