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

    private var tripItems: [GroceryItem] { items.filter { $0.trip == trip } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Trip", selection: $trip) {
                Text("Trip 1 · Sun").tag(1)
                Text("Trip 2 · Wed").tag(2)
            }
            .pickerStyle(.segmented)

            recipesRow
            listCard
        }
        .sheet(isPresented: $showAddRecipe) {
            AddRecipeSheet()
        }
    }

    // MARK: Recipes

    private var recipesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "This week's recipes")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recipes) { recipe in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name)
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text("\(recipe.servings) \(recipe.slot.rawValue)\(recipe.servings == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                            if !recipe.note.isEmpty {
                                Text(recipe.note)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.foodText)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(width: 120, alignment: .leading)
                        .padding(12)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contextMenu {
                            Button("Delete", role: .destructive) { context.delete(recipe) }
                        }
                    }
                    Button {
                        showAddRecipe = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("+ New recipe")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Palette.ink)
                            Text("Pick ones that reheat well")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(width: 120, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.faint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                    .onSubmit(addItem)
                TextField("Qty", text: $newQuantity)
                    .frame(width: 56)
                Menu {
                    ForEach(Self.sections, id: \.self) { s in
                        Button(s) { newSection = s }
                    }
                } label: {
                    Text(newSection)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.foodText)
                }
                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.food)
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add item")
            }
            .font(.subheadline)
            .padding(10)
            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
            item.isDone.toggle()
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
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isDone ? Palette.faint : Palette.ink)
                    .strikethrough(item.isDone)
                Spacer()
                Text(item.quantity)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { context.delete(item) }
        }
    }
}

struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var servings = 4
    @State private var slot: MealSlot = .dinner
    @State private var note = "Reheats well"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $name)
                    Stepper("Makes \(servings) meal\(servings == 1 ? "" : "s")", value: $servings, in: 1...14)
                    Picker("For", selection: $slot) {
                        ForEach(MealSlot.allCases) { s in Text(s.title).tag(s) }
                    }
                }
                Section("Note") {
                    TextField("e.g. Reheats well, Freezes well", text: $note)
                }
            }
            .navigationTitle("New recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Recipe(name: name.trimmingCharacters(in: .whitespaces),
                                              servings: servings, slot: slot, note: note))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
