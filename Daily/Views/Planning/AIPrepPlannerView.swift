import SwiftUI
import SwiftData

struct PrepPlan: Decodable {
    struct PlannedRecipe: Decodable {
        var name: String
        var servings: Double?
        var ingredients: [String]
        var steps: [String]
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var note: String?
        var isExisting: Bool?
    }
    struct Assignment: Decodable {
        var day: String
        var slot: String
        var recipe: String
    }
    struct Grocery: Decodable {
        var name: String
        var quantity: String?
        var section: String?
    }
    var summary: String
    var recipes: [PlannedRecipe]
    var assignments: [Assignment]
    var groceries: [Grocery]
}

/// Claude plans a Sunday prep: picks recipes that reheat well and hit your goals,
/// fills empty lunch/dinner slots for the week, and builds the grocery list.
struct AIPrepPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var plans: [MealPlan]
    @Query private var groceries: [GroceryItem]

    /// The 7 days being planned.
    let days: [Date]

    @State private var lunches = true
    @State private var dinners = true
    @State private var weekendsToo = false
    @State private var recipeCount = 2
    @State private var reuse = true
    @State private var fridge = ""
    @State private var preferences = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var result: PrepPlan?
    @State private var applied = false

    private let cal = Calendar.current

    private var openSlots: [(day: Date, slot: MealSlot)] {
        var out: [(day: Date, slot: MealSlot)] = []
        for day in days {
            let weekday = cal.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            if isWeekend && !weekendsToo { continue }
            if day < cal.startOfDay(for: Date()) { continue }
            for slot in [MealSlot.lunch, .dinner] {
                if slot == .lunch && !lunches { continue }
                if slot == .dinner && !dinners { continue }
                let key = DayKey.of(day)
                if plans.contains(where: { $0.dayKey == key && $0.slot == slot }) { continue }
                out.append((day: day, slot: slot))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                if !Keychain.hasKey {
                    Section {
                        Text("This uses Claude. Add your Anthropic API key in Commute → Settings first.")
                            .font(.footnote)
                            .foregroundStyle(Palette.gymText)
                    }
                }
                Section {
                    Toggle("Lunches", isOn: $lunches)
                    Toggle("Dinners", isOn: $dinners)
                    Toggle("Include weekends", isOn: $weekendsToo)
                    Stepper("Cook \(recipeCount) recipe\(recipeCount == 1 ? "" : "s")", value: $recipeCount, in: 1...4)
                    Toggle("Reuse my saved recipes", isOn: $reuse)
                } header: {
                    Text("What to cover")
                } footer: {
                    Text("\(openSlots.count) empty meal\(openSlots.count == 1 ? "" : "s") to fill. Already-planned meals and eat-outs are left alone. Goals: \(MySchedule.calorieGoal.formatted()) cal and \(MySchedule.proteinGoal)g protein a day.")
                }
                Section {
                    TextField("Already have (e.g. rice, eggs, half a bag of spinach)", text: $fridge, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Cravings or things to avoid", text: $preferences, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Optional")
                }
                Section {
                    Button {
                        run()
                    } label: {
                        HStack {
                            Text(working ? "Planning…" : (result == nil ? "Make my plan" : "Try again"))
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working || openSlots.isEmpty)
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Palette.gymText)
                    }
                }

                if let result {
                    Section("The plan") {
                        Text(result.summary).font(.subheadline)
                    }
                    Section("Cook on Sunday") {
                        ForEach(result.recipes, id: \.name) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name + ((r.isExisting ?? false) ? " · saved" : " · new"))
                                    .font(.subheadline.weight(.semibold))
                                Text("Makes \(Int(r.servings ?? 1))" + (r.calories.map { " · \(Int($0)) cal, \(Int(r.protein ?? 0))g protein per serving" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    Section("Meals") {
                        ForEach(Array(result.assignments.enumerated()), id: \.offset) { _, a in
                            HStack {
                                Text(dayLabel(a.day) + " " + a.slot.capitalized)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.muted)
                                Spacer()
                                Text(a.recipe).font(.footnote.weight(.semibold))
                            }
                        }
                    }
                    Section {
                        Text("\(result.groceries.count) items to buy")
                    } header: {
                        Text("Groceries")
                    } footer: {
                        Text(applied ? "Added to your week and to the Trip 1 list." : "Apply adds the new recipes, fills the meals, and puts the groceries on the Trip 1 list.")
                    }
                }
            }
            .navigationTitle("Plan my prep")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(applied ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(result == nil || applied)
                }
            }
        }
    }

    private func dayLabel(_ key: String) -> String {
        guard let day = days.first(where: { DayKey.of($0) == key }) else { return key }
        return day.formatted(.dateTime.weekday(.abbreviated))
    }

    private static func describe(_ r: Recipe) -> String {
        var line = "- " + r.name + ": makes " + r.amountLabel(Double(r.servings))
        line += " (\(r.mealCount) meals)"
        if let macros = r.macroLine { line += ", " + macros + " per " + r.unitLabel(for: 1) }
        if !r.note.isEmpty { line += ", " + r.note }
        return line
    }

    private func run() {
        working = true
        errorText = nil
        let slotList = openSlots.map { "\(DayKey.of($0.day)) (\($0.day.formatted(.dateTime.weekday(.wide)))) \($0.slot.rawValue)" }
        let saved = reuse ? recipes.map(Self.describe).joined(separator: "\n") : ""
        let prompt = """
        Plan a Sunday meal prep for one person who works an office job, goes to the gym 2-3 times a week, \
        and wants to eat out less. Meals must reheat well (packed lunches, microwave dinners).

        Daily goals: about \(MySchedule.calorieGoal) calories and \(MySchedule.proteinGoal) g protein.
        Cook exactly \(recipeCount) recipe(s) in about 2 hours total, with enough servings to cover every slot below.
        Shop in 1 trip if possible; use simple ingredients from a normal grocery store.

        Fill these meal slots (use the date as "day" and "lunch"/"dinner" as "slot"):
        \(slotList.joined(separator: "\n"))

        \(saved.isEmpty ? "" : "Saved recipes you may reuse (keep the exact name and set isExisting true):\n" + saved)
        \(fridge.isEmpty ? "" : "Already in the kitchen (use these and leave them off the grocery list): " + fridge)
        \(preferences.isEmpty ? "" : "Preferences: " + preferences)

        For new recipes include full ingredients with quantities, clear steps with times, and nutrition per serving. \
        Spread recipes so the same meal isn't eaten for both lunch and dinner on one day when possible. \
        The grocery list should combine everything needed for new recipes (and saved ones being reused), \
        with quantities, minus what's already in the kitchen. Section is one of Produce, Protein, Dairy, Pantry, Frozen, Other.
        """

        let recipeSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "servings": ["type": "number"],
                "ingredients": ["type": "array", "items": ["type": "string"]] as [String: Any],
                "steps": ["type": "array", "items": ["type": "string"]] as [String: Any],
                "calories": ["type": "number"],
                "protein": ["type": "number"],
                "carbs": ["type": "number"],
                "fat": ["type": "number"],
                "note": ["type": "string", "description": "e.g. Reheats well"],
                "isExisting": ["type": "boolean"]
            ] as [String: Any],
            "required": ["name", "servings", "ingredients", "steps", "calories", "protein", "carbs", "fat", "isExisting"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "summary": ["type": "string", "description": "2-3 sentences: what to cook, rough prep order, how it hits the goals"],
                "recipes": ["type": "array", "items": recipeSchema] as [String: Any],
                "assignments": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "day": ["type": "string", "description": "yyyy-MM-dd from the slot list"],
                        "slot": ["type": "string", "enum": ["lunch", "dinner"]] as [String: Any],
                        "recipe": ["type": "string", "description": "Exact recipe name"]
                    ] as [String: Any],
                    "required": ["day", "slot", "recipe"]
                ] as [String: Any]] as [String: Any],
                "groceries": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "quantity": ["type": "string"],
                        "section": ["type": "string"]
                    ] as [String: Any],
                    "required": ["name"]
                ] as [String: Any]] as [String: Any]
            ] as [String: Any],
            "required": ["summary", "recipes", "assignments", "groceries"]
        ]

        Task {
            do {
                result = try await AIClient.structured(prompt: prompt, toolName: "prep_plan",
                                                       toolDescription: "Save the meal prep plan",
                                                       schema: schema, as: PrepPlan.self, maxTokens: 12000)
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }

    private func apply() {
        guard let result else { return }
        for r in result.recipes where !recipes.contains(where: { $0.name == r.name }) {
            let recipe = Recipe(name: r.name, servings: max(1, Int((r.servings ?? 1).rounded())),
                                slot: .dinner, note: r.note ?? "Reheats well",
                                ingredients: r.ingredients.joined(separator: "\n"))
            recipe.stepsRaw = r.steps.joined(separator: "\n")
            recipe.caloriesPerServing = r.calories.map { Int($0.rounded()) }
            recipe.proteinPerServing = r.protein.map { Int($0.rounded()) }
            recipe.carbsPerServing = r.carbs.map { Int($0.rounded()) }
            recipe.fatPerServing = r.fat.map { Int($0.rounded()) }
            context.insert(recipe)
        }
        for a in result.assignments {
            guard let slot = MealSlot(rawValue: a.slot.lowercased()) else { continue }
            if plans.contains(where: { $0.dayKey == a.day && $0.slot == slot }) { continue }
            context.insert(MealPlan(dayKey: a.day, slot: slot, title: a.recipe))
        }
        let open = Set(groceries.filter { $0.trip == 1 && !$0.isDone }.map { $0.name.lowercased() })
        for g in result.groceries where !open.contains(g.name.lowercased()) {
            let section = GroceriesSection.sections.contains(g.section ?? "") ? (g.section ?? "Other") : GroceryParser.section(for: g.name)
            context.insert(GroceryItem(name: g.name, quantity: g.quantity ?? "", section: section, trip: 1))
        }
        applied = true
    }
}
