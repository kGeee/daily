import SwiftUI
import SwiftData

struct GroceriesSection: View {
    static let sections = ["Produce", "Protein", "Dairy", "Pantry", "Frozen", "Other"]

    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryItem.createdAt) private var items: [GroceryItem]
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]

    @State private var trip = 1
    @State private var newName = ""
    @State private var newQuantity = ""
    @State private var newSection = "Produce"
    @State private var showAddRecipe = false
    @State private var editingRecipe: Recipe?
    @State private var viewingRecipe: Recipe?
    @State private var showImport = false
    @State private var showWeekPlan = false

    private var tripItems: [GroceryItem] { items.filter { $0.trip == trip } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PillSegment([1, 2], selection: $trip) { $0 == 1 ? "Trip 1 · Sun" : "Trip 2 · Wed" }

            Button {
                showWeekPlan = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text("Plan this week's meals")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .foregroundStyle(Palette.foodText)
                .padding(14)
                .background(Palette.foodTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            recipesRow
            listCard
        }
        .sheet(isPresented: $showAddRecipe) {
            AddRecipeSheet(recipe: nil)
        }
        .sheet(item: $editingRecipe) { recipe in
            AddRecipeSheet(recipe: recipe)
        }
        .sheet(item: $viewingRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .sheet(isPresented: $showImport) {
            ImportRecipeView()
        }
        .sheet(isPresented: $showWeekPlan) {
            WeekPlanView()
        }
    }

    // MARK: Recipes

    private var recipesRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "This week's recipes")
                Spacer()
                if !recipes.isEmpty {
                    Text("\(recipes.reduce(0) { $0 + $1.mealCount }) meals")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.foodText)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recipes) { recipe in
                        recipeCard(recipe)
                    }
                    addCard(title: "New recipe", symbol: "plus", subtitle: "Pick ones that reheat well") {
                        showAddRecipe = true
                    }
                    addCard(title: "Import", symbol: "square.and.arrow.down",
                            subtitle: "From an Instagram reel, screenshot or text") {
                        showImport = true
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
    }

    private static let recipeCardSize = CGSize(width: 168, height: 158)

    private func recipeCard(_ recipe: Recipe) -> some View {
        Button {
            viewingRecipe = recipe
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: recipe.slot.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.food)
                        .frame(width: 24, height: 24)
                        .background(Palette.foodTint, in: Circle())
                    Text(recipe.hasCustomUnit
                         ? "\(recipe.servings) \(recipe.unitLabel(for: Double(recipe.servings))) · \(recipe.mealCount) \(recipe.slot.rawValue)\(recipe.mealCount == 1 ? "" : "s")"
                         : "\(recipe.mealCount) \(recipe.slot.rawValue)\(recipe.mealCount == 1 ? "" : "s")")
                        .lineLimit(1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                Text(recipe.name)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !recipe.note.isEmpty {
                    Text(recipe.note)
                        .font(.caption)
                        .foregroundStyle(Palette.foodText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(recipe.macroLine ?? (recipe.ingredients.isEmpty ? "No ingredients yet" : "\(recipe.ingredients.count) ingredients"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: Self.recipeCardSize.width, height: Self.recipeCardSize.height, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "book") { viewingRecipe = recipe }
            Button("Edit", systemImage: "pencil") { editingRecipe = recipe }
            Button("Add ingredients to this trip", systemImage: "cart.badge.plus") { addIngredients(of: recipe) }
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(recipe) }
        }
    }

    private func addCard(title: String, symbol: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.foodText)
                    .frame(width: 32, height: 32)
                    .background(Palette.foodTint, in: Circle())
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: Self.recipeCardSize.width * 0.8, height: Self.recipeCardSize.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.faint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var listCard: some View {
        let doneCount = tripItems.filter { $0.isDone }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Shopping list")
                Spacer()
                Text("\(doneCount) of \(tripItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }

            HStack(spacing: 8) {
                TextField("Add item", text: $newName)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                TextField("Qty", text: $newQuantity)
                    .frame(width: 50)
                    .foregroundStyle(Palette.muted)
                Menu {
                    ForEach(Self.sections, id: \.self) { s in
                        Button(s) { newSection = s }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(newSection)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.foodText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Palette.foodTint, in: Capsule())
                }
                Button(action: addItem) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 30, height: 30)
                        .background(Palette.food, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Add item")
            }
            .font(.subheadline)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 48)
            .background(Palette.card2, in: Capsule())

            if tripItems.isEmpty {
                Text("Nothing on this trip's list yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.faint)
                    .padding(.vertical, 8)
            }

            ForEach(Self.sections, id: \.self) { section in
                let group = tripItems.filter { $0.section == section }
                if !group.isEmpty {
                    SectionLabel(text: section, color: Palette.foodText)
                        .padding(.top, 6)
                    ForEach(group) { item in
                        GroceryRow(item: item)
                    }
                }
            }

            if doneCount > 0 {
                Button("Clear checked items") {
                    for item in tripItems where item.isDone {
                        context.delete(item)
                    }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.foodText)
                .padding(.top, 6)
            }
        }
        .card()
    }

    private func addIngredients(of recipe: Recipe) {
        let open = Set(tripItems.filter { !$0.isDone }.map { $0.name.lowercased() })
        for line in recipe.ingredients {
            let parsed = GroceryParser.parse(line)
            guard !open.contains(parsed.name.lowercased()) else { continue }
            context.insert(GroceryItem(name: parsed.name, quantity: parsed.quantity, section: parsed.section, trip: trip))
        }
    }

    private func addItem() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(GroceryItem(name: name,
                                   quantity: newQuantity.trimmingCharacters(in: .whitespaces),
                                   section: newSection,
                                   trip: trip))
        newName = ""
        newQuantity = ""
    }
}

struct GroceryRow: View {
    @Environment(\.modelContext) private var context
    let item: GroceryItem

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { item.isDone.toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.food, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(item.isDone ? Palette.food : Color.clear)
                        )
                    if item.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isDone ? Palette.faint : Palette.ink)
                        .strikethrough(item.isDone)
                        .lineLimit(2)
                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .animation(.snappy(duration: 0.2), value: item.isDone)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.isDone)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
        }
    }
}

/// Turns a line like "2 lb chicken thighs" into a grocery item with a guessed store section.
enum GroceryParser {
    private static let units: Set<String> = [
        "lb", "lbs", "oz", "g", "kg", "cup", "cups", "can", "cans", "tbsp", "tsp",
        "bunch", "bunches", "clove", "cloves", "pack", "packs", "bag", "bags", "jar", "jars", "dozen", "head", "heads"
    ]

    static func parse(_ line: String) -> (name: String, quantity: String, section: String) {
        let words = line.split(separator: " ").map(String.init)
        var quantity: [String] = []
        var index = 0
        if let first = words.first, first.first?.isNumber == true {
            quantity.append(first)
            index = 1
            if words.count > 1, units.contains(words[1].lowercased()) {
                quantity.append(words[1])
                index = 2
            }
        }
        let rest = words.dropFirst(index).joined(separator: " ")
        let name = rest.isEmpty ? line : rest.prefix(1).uppercased() + rest.dropFirst()
        return (name, quantity.joined(separator: " "), section(for: name))
    }

    static func section(for name: String) -> String {
        let n = name.lowercased()
        let groups: [(String, [String])] = [
            ("Protein", ["chicken", "beef", "turkey", "pork", "salmon", "fish", "shrimp", "tofu", "egg", "steak", "sausage", "tuna"]),
            ("Dairy", ["milk", "cheese", "yogurt", "butter", "cream", "feta", "parmesan"]),
            ("Frozen", ["frozen", "ice"]),
            ("Produce", ["onion", "garlic", "pepper", "tomato", "lettuce", "spinach", "kale", "broccoli", "carrot",
                         "potato", "cilantro", "lime", "lemon", "avocado", "cucumber", "zucchini", "mushroom",
                         "apple", "banana", "berries", "ginger", "scallion", "celery", "cabbage", "herb", "basil"])
        ]
        for (section, words) in groups where words.contains(where: { n.contains($0) }) {
            return section
        }
        return "Pantry"
    }
}

struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let recipe: Recipe?

    @State private var name: String
    @State private var servings: Int
    @State private var yieldUnit: String
    @State private var unitsPerMeal: Double
    @State private var slot: MealSlot
    @State private var note: String
    @State private var ingredients: String
    @State private var steps: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var estimating = false
    @State private var errorText: String?

    init(recipe: Recipe?) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _yieldUnit = State(initialValue: recipe?.yieldUnit ?? "")
        _unitsPerMeal = State(initialValue: recipe?.unitsPerMeal ?? 1)
        _slot = State(initialValue: recipe?.slot ?? .dinner)
        _note = State(initialValue: recipe?.note ?? "Reheats well")
        _ingredients = State(initialValue: recipe?.ingredientsRaw ?? "")
        _steps = State(initialValue: recipe?.stepsRaw ?? "")
        _calories = State(initialValue: recipe?.caloriesPerServing.map(String.init) ?? "")
        _protein = State(initialValue: recipe?.proteinPerServing.map(String.init) ?? "")
        _carbs = State(initialValue: recipe?.carbsPerServing.map(String.init) ?? "")
        _fat = State(initialValue: recipe?.fatPerServing.map(String.init) ?? "")
    }

    private var ingredientLines: [String] {
        ingredients.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func estimate() {
        estimating = true
        errorText = nil
        Task {
            do {
                let result = try await RecipeAI.estimate(recipe: name, servings: servings, ingredients: ingredientLines)
                calories = String(Int(result.calories.rounded()))
                protein = String(Int(result.protein.rounded()))
                carbs = String(Int(result.carbs.rounded()))
                fat = String(Int(result.fat.rounded()))
            } catch {
                errorText = error.localizedDescription
            }
            estimating = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $name)
                    Picker("For", selection: $slot) {
                        ForEach(MealSlot.allCases) { s in Text(s.title).tag(s) }
                    }
                }
                Section {
                    HStack {
                        Text("Makes")
                        TextField("4", value: $servings, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        TextField("servings", text: $yieldUnit)
                            .textInputAutocapitalization(.never)
                    }
                    if !yieldUnit.trimmingCharacters(in: .whitespaces).isEmpty {
                        Stepper(value: $unitsPerMeal, in: 0.5...100, step: unitsPerMeal < 3 ? 0.5 : 1) {
                            Text("One meal is \(unitsPerMeal == unitsPerMeal.rounded() ? String(Int(unitsPerMeal)) : String(format: "%.1f", unitsPerMeal)) \(yieldUnit)")
                        }
                    }
                } header: {
                    Text("How much it makes")
                } footer: {
                    Text(yieldUnit.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Leave the second box empty for servings, or name what it makes (nuggets, cookies, egg bites) to log any amount."
                         : "That's \(max(1, Int((Double(max(servings, 1)) / max(unitsPerMeal, 0.1)).rounded(.down)))) meals. Nutrition below is per one of the \(yieldUnit).")
                }
                Section("Note") {
                    TextField("e.g. Reheats well, Freezes well", text: $note)
                }
                Section {
                    TextField("2 lb chicken thighs\n1 can black beans\n1 bunch cilantro", text: $ingredients, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("One per line. Add them to your grocery list from the recipe card or the week plan.")
                }
                Section {
                    TextField("Season and sear the chicken, 5 min per side\nSimmer the beans for 10 minutes", text: $steps, axis: .vertical)
                        .lineLimit(4...16)
                } header: {
                    Text("Steps")
                } footer: {
                    Text("One step per line. Times like \"10 minutes\" get a timer button in cooking mode.")
                }
                Section {
                    macroField("Calories", text: $calories)
                    macroField("Protein (g)", text: $protein)
                    macroField("Carbs (g)", text: $carbs)
                    macroField("Fat (g)", text: $fat)
                    Button {
                        estimate()
                    } label: {
                        HStack {
                            Text(estimating ? "Estimating…" : "Estimate with AI")
                            Spacer()
                            if estimating { ProgressView() }
                        }
                    }
                    .disabled(estimating || ingredientLines.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Palette.gymText)
                    }
                } header: {
                    Text(yieldUnit.trimmingCharacters(in: .whitespaces).isEmpty ? "Nutrition per serving" : "Nutrition per one of the \(yieldUnit)")
                }
            }
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let recipe {
            recipe.name = trimmed
            recipe.servings = max(servings, 1)
            recipe.slotRaw = slot.rawValue
            recipe.note = note
            recipe.ingredientsRaw = ingredients
            apply(to: recipe)
        } else {
            let newRecipe = Recipe(name: trimmed, servings: max(servings, 1), slot: slot, note: note, ingredients: ingredients)
            apply(to: newRecipe)
            context.insert(newRecipe)
        }
        dismiss()
    }

    private func apply(to recipe: Recipe) {
        recipe.yieldUnit = yieldUnit.trimmingCharacters(in: .whitespaces)
        recipe.unitsPerMeal = recipe.yieldUnit.isEmpty ? 1 : unitsPerMeal
        recipe.stepsRaw = steps
        recipe.caloriesPerServing = Int(calories.trimmingCharacters(in: .whitespaces))
        recipe.proteinPerServing = Int(protein.trimmingCharacters(in: .whitespaces))
        recipe.carbsPerServing = Int(carbs.trimmingCharacters(in: .whitespaces))
        recipe.fatPerServing = Int(fat.trimmingCharacters(in: .whitespaces))
    }

    private func macroField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}
