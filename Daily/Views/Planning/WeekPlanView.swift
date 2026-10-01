import SwiftUI
import SwiftData

/// Plan a week at a glance: day types, gym rotation, lunches and dinners, events,
/// and push the planned recipes' ingredients onto the grocery list.
struct WeekPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var plans: [MealPlan]
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var events: [CustomEvent]
    @Query private var groceries: [GroceryItem]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    @State private var weekOffset: Int
    @State private var groceryMessage: String?

    init(startOnNextWeek: Bool = false) {
        _weekOffset = State(initialValue: startOnNextWeek ? 1 : 0)
    }

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }
    private let cal = Calendar.current

    private func weekDays(offset: Int) -> [Date] {
        let today = cal.startOfDay(for: Date())
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = cal.date(byAdding: .weekOfYear, value: offset, to: thisWeek) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var days: [Date] { weekDays(offset: weekOffset) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Week", selection: $weekOffset) {
                        Text("This week").tag(0)
                        Text("Next week").tag(1)
                    }
                    .pickerStyle(.segmented)

                    summaryCard
                    let gym = gymRotation()
                    ForEach(days, id: \.self) { day in
                        dayCard(day, gymName: gym[DayKey.of(day)])
                    }
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Plan the week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Summary

    private var weekPlans: [MealPlan] {
        let keys = Set(days.map { DayKey.of($0) })
        return plans.filter { keys.contains($0.dayKey) }
    }

    private var summaryCard: some View {
        let types = days.compactMap { planner.type(for: $0) }
        let gymCount = types.filter { $0 == .gym }.count
        let shuttleCount = types.filter { $0 == .shuttle }.count
        let caltrainCount = types.filter { $0 == .caltrain }.count
        let planned = weekPlans.count
        let eatOut = weekPlans.filter { $0.isEatingOut }.count
        let usage = recipeUsage()

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "This plan")
            HStack(spacing: 8) {
                summaryChip("\(gymCount)", "gym", Palette.gymText)
                summaryChip("\(shuttleCount)", "shuttle", Palette.commuteText)
                summaryChip("\(caltrainCount)", "Caltrain", Palette.muted)
            }
            HStack(spacing: 8) {
                summaryChip("\(planned)/14", "meals planned", Palette.foodText)
                summaryChip("\(eatOut)", "eating out", eatOut > MySchedule.eatOutGoalPerWeek ? Palette.gymText : Palette.muted)
            }
            if !usage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(usage, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(item.planned) planned · makes \(item.servings)")
                                .font(.caption)
                                .foregroundStyle(item.planned > item.servings ? Palette.gymText : Palette.muted)
                        }
                    }
                }
                .padding(.top, 2)
                Button {
                    addIngredientsToList(usage.map { $0.name })
                } label: {
                    Label("Add ingredients to grocery list", systemImage: "cart.badge.plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.food, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                if let groceryMessage {
                    Text(groceryMessage)
                        .font(.caption)
                        .foregroundStyle(Palette.foodText)
                }
            } else {
                Text("Pick lunches and dinners below. Add recipes in Food → Plan & groceries.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .card()
    }

    private func summaryChip(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.card2, in: Capsule())
    }

    private struct Usage {
        let name: String
        let planned: Int
        let servings: Int
    }

    private func recipeUsage() -> [Usage] {
        let counts = Dictionary(grouping: weekPlans.filter { !$0.isEatingOut }, by: { $0.title }).mapValues { $0.count }
        return counts.keys.sorted().map { name in
            Usage(name: name, planned: counts[name] ?? 0,
                  servings: recipes.first { $0.name == name }?.servings ?? 0)
        }
    }

    private func addIngredientsToList(_ recipeNames: [String]) {
        let open = Set(groceries.filter { $0.trip == 1 && !$0.isDone }.map { $0.name.lowercased() })
        var added = 0
        for name in recipeNames {
            guard let recipe = recipes.first(where: { $0.name == name }) else { continue }
            for line in recipe.ingredients {
                let parsed = GroceryParser.parse(line)
                guard !open.contains(parsed.name.lowercased()) else { continue }
                context.insert(GroceryItem(name: parsed.name, quantity: parsed.quantity, section: parsed.section, trip: 1))
                added += 1
            }
        }
        groceryMessage = added == 0
            ? "Nothing new to add. Recipes need ingredients listed, or they're already on the list."
            : "Added \(added) item\(added == 1 ? "" : "s") to Trip 1."
    }

    // MARK: Gym rotation

    /// Which workout lands on each gym day, continuing the Back → Chest → Legs rotation.
    private func gymRotation() -> [String: String] {
        let strength = templates.filter { !$0.isCardio }.sorted { $0.order < $1.order }
        guard !strength.isEmpty else { return [:] }
        var result: [String: String] = [:]
        let today = cal.startOfDay(for: Date())
        let next = WorkoutTemplate.nextName(templates: templates, sessions: sessions)
        var index = strength.firstIndex { $0.name == next } ?? 0

        for day in weekDays(offset: 0) + weekDays(offset: 1) where planner.type(for: day) == .gym {
            let key = DayKey.of(day)
            if let done = sessions.first(where: { cal.isDate($0.date, inSameDayAs: day) }) {
                result[key] = done.templateName
            } else if day >= today {
                result[key] = strength[index % strength.count].name
                index += 1
            }
        }
        return result
    }

    // MARK: Day card

    private func commuteLine(for day: Date, type: DayType?, gymName: String?) -> String {
        switch type {
        case .shuttle?:
            return "Shuttle \(MySchedule.shuttleOut.label) · home \(MySchedule.shuttleHome.label)"
        case .gym?:
            let train = MySchedule.caltrainAfterGym
            return "Shuttle \(MySchedule.shuttleOut.label) · \(gymName ?? "Gym") \(MySchedule.gymStart.label) · train \(train.isEstimate ? "~" : "")\(train.time.label)"
        case .caltrain?:
            let out = MySchedule.caltrainOut
            let home = MySchedule.caltrainAfterWork
            return "Train \(out.isEstimate ? "~" : "")\(out.time.label) · home \(home.isEstimate ? "~" : "")\(home.time.label)"
        case nil:
            return cal.component(.weekday, from: day) == 1
                ? "Meal prep \(MySchedule.prepStart.label) – \(MySchedule.prepEnd.label)"
                : "Free day"
        }
    }

    private func dayCard(_ day: Date, gymName: String?) -> some View {
        let type = planner.type(for: day)
        let isToday = cal.isDateInToday(day)
        let isPast = day < cal.startOfDay(for: Date())
        let dayEvents = events.filter { $0.occurs(on: day) }.map { $0.block(on: day) }.sorted { $0.start < $1.start }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(isPast ? Palette.faint : Palette.ink)
                    Text(day.formatted(.dateTime.month(.abbreviated).day()) + (isToday ? " · Today" : ""))
                        .font(.caption)
                        .foregroundStyle(isToday ? Palette.commuteText : Palette.muted)
                }
                Spacer()
                if let type {
                    Menu {
                        ForEach(DayType.allCases) { t in
                            Button(t.title) { setType(t, on: day) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(type.color).frame(width: 8, height: 8)
                            Text(type.short).font(.footnote.weight(.bold))
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(type.tint, in: Capsule())
                    }
                } else {
                    Text("Weekend")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.muted)
                }
            }

            Text(commuteLine(for: day, type: type, gymName: gymName))
                .font(.caption)
                .foregroundStyle(Palette.muted)

            HStack(spacing: 8) {
                mealMenu(day: day, slot: .lunch)
                mealMenu(day: day, slot: .dinner)
            }
            let plannedCalories = [MealSlot.lunch, .dinner]
                .compactMap { plan(for: day, slot: $0) }
                .compactMap { p in recipes.first { $0.name == p.title }?.caloriesPerServing }
                .reduce(0, +)
            if plannedCalories > 0 {
                Text("~\(plannedCalories) cal planned for lunch + dinner")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }

            if !dayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dayEvents) { event in
                        HStack(spacing: 6) {
                            Circle().fill(event.category.color).frame(width: 6, height: 6)
                            Text(event.start.formatted(date: .omitted, time: .shortened) + " · " + event.title)
                                .font(.caption)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isToday ? Palette.commute : Color.clear, lineWidth: 2)
        )
    }

    private func plan(for day: Date, slot: MealSlot) -> MealPlan? {
        let key = DayKey.of(day)
        return plans.first { $0.dayKey == key && $0.slot == slot }
    }

    private func mealMenu(day: Date, slot: MealSlot) -> some View {
        let current = plan(for: day, slot: slot)

        return Menu {
            ForEach(recipes) { recipe in
                Button(recipe.name) { setPlan(day: day, slot: slot, title: recipe.name) }
            }
            Button(MealPlan.eatOut) { setPlan(day: day, slot: slot, title: MealPlan.eatOut) }
            if current != nil {
                Button("Clear", role: .destructive) { setPlan(day: day, slot: slot, title: nil) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.muted)
                Text(current?.title ?? "Plan…")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(current == nil ? Palette.faint : (current?.isEatingOut == true ? Palette.gymText : Palette.foodText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Changes

    private func setType(_ type: DayType, on day: Date) {
        let key = DayKey.of(day)
        if let existing = overrides.first(where: { $0.dayKey == key }) {
            existing.typeRaw = type.rawValue
        } else {
            context.insert(DayTypeOverride(dayKey: key, typeRaw: type.rawValue))
        }
    }

    private func setPlan(day: Date, slot: MealSlot, title: String?) {
        let existing = plan(for: day, slot: slot)
        if let title {
            if let existing {
                existing.title = title
            } else {
                context.insert(MealPlan(dayKey: DayKey.of(day), slot: slot, title: title))
            }
        } else if let existing {
            context.delete(existing)
        }
    }
}
