import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var recipe: Recipe

    @State private var cooking = false
    @State private var editing = false
    @State private var estimating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        Text("Makes \(recipe.servings) · \(recipe.slot.title)" + (recipe.note.isEmpty ? "" : " · " + recipe.note))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }

                    Button {
                        cooking = true
                    } label: {
                        Label("Start cooking", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(Palette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Palette.food, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    nutritionCard

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Ingredients")
                        if recipe.ingredients.isEmpty {
                            Text("None yet. Tap Edit to add them.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.faint)
                        }
                        ForEach(recipe.ingredients, id: \.self) { line in
                            Text("• " + line)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Steps")
                        if recipe.steps.isEmpty {
                            Text("None yet. Tap Edit to add them, one per line.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.faint)
                        }
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(Palette.onAccent)
                                    .frame(width: 22, height: 22)
                                    .background(Palette.food, in: Circle())
                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .card()

                    if let url = URL(string: recipe.sourceURL), !recipe.sourceURL.isEmpty {
                        Link(destination: url) {
                            Label("Open original post", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.commuteText)
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
            }
            .fullScreenCover(isPresented: $cooking) {
                CookModeView(recipe: recipe)
            }
            .sheet(isPresented: $editing) {
                AddRecipeSheet(recipe: recipe)
            }
        }
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Per serving")
                Spacer()
                if estimating {
                    ProgressView()
                } else {
                    Button(recipe.hasNutrition ? "Re-estimate" : "Estimate with AI") { estimate() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.foodText)
                        .disabled(recipe.ingredients.isEmpty)
                }
            }
            if recipe.hasNutrition {
                HStack(spacing: 8) {
                    MacroTile(label: "Calories", value: recipe.caloriesPerServing.map { "\($0)" } ?? "—", color: Palette.ink)
                    MacroTile(label: "Protein", value: recipe.proteinPerServing.map { "\($0)g" } ?? "—", color: Palette.foodText)
                    MacroTile(label: "Carbs", value: recipe.carbsPerServing.map { "\($0)g" } ?? "—", color: Palette.commuteText)
                    MacroTile(label: "Fat", value: recipe.fatPerServing.map { "\($0)g" } ?? "—", color: Palette.gymText)
                }
                Text("Estimates. Logging this recipe as a meal fills these in.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            } else {
                Text(recipe.ingredients.isEmpty
                     ? "Add ingredients, then estimate calories and macros."
                     : "No nutrition yet. Estimate it, or enter it under Edit.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.faint)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Palette.gymText)
            }
        }
        .card()
    }

    private func estimate() {
        estimating = true
        errorText = nil
        Task {
            do {
                let result = try await RecipeAI.estimate(recipe: recipe.name, servings: recipe.servings,
                                                         ingredients: recipe.ingredients)
                recipe.caloriesPerServing = Int(result.calories.rounded())
                recipe.proteinPerServing = Int(result.protein.rounded())
                recipe.carbsPerServing = Int(result.carbs.rounded())
                recipe.fatPerServing = Int(result.fat.rounded())
            } catch {
                errorText = error.localizedDescription
            }
            estimating = false
        }
    }
}

struct MacroTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.heavy))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Import

struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var link = ""
    @State private var text = ""
    @State private var working = false
    @State private var status: String?
    @State private var parsed: ParsedRecipe?
    @State private var slot: MealSlot = .dinner

    var body: some View {
        NavigationStack {
            Form {
                if !Keychain.hasKey {
                    Section {
                        Text("Importing uses Claude to read the post. Add your Anthropic API key in Commute → Settings first.")
                            .font(.footnote)
                            .foregroundStyle(Palette.gymText)
                    }
                }

                Section {
                    TextField("Instagram reel link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("1 · The post")
                } footer: {
                    Text("In Instagram tap Share → Copy link, then paste here. The link is saved so you can rewatch.")
                }

                Section {
                    TextField("Paste the caption or recipe text here", text: $text, axis: .vertical)
                        .lineLimit(5...14)
                } header: {
                    Text("2 · The recipe text")
                } footer: {
                    Text("Instagram often hides captions from apps. If the import can't read it, open the reel, tap … → Copy caption (or select the caption text) and paste it here. Recipes that are only spoken in the video need the steps typed or pasted.")
                }

                Section {
                    Button {
                        runImport()
                    } label: {
                        HStack {
                            Text(working ? "Reading recipe…" : "Read recipe")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working || (link.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty))
                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }

                if let parsed {
                    Section("Preview") {
                        Text(parsed.name).font(.headline)
                        Text("Makes \(Int(parsed.servings ?? 1)) · \(parsed.ingredients.count) ingredients · \(parsed.steps.count) steps")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                        if let cal = parsed.calories {
                            Text("~\(Int(cal.rounded())) cal · \(Int((parsed.protein ?? 0).rounded()))g protein · \(Int((parsed.carbs ?? 0).rounded()))g carbs · \(Int((parsed.fat ?? 0).rounded()))g fat per serving")
                                .font(.subheadline)
                        }
                        Picker("For", selection: $slot) {
                            ForEach(MealSlot.allCases) { s in Text(s.title).tag(s) }
                        }
                        ForEach(parsed.ingredients, id: \.self) { Text("• " + $0).font(.footnote) }
                    }
                }
            }
            .navigationTitle("Import recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsed == nil)
                }
            }
        }
    }

    private func pasteFromClipboard() {
        guard let pasted = UIPasteboard.general.string else { return }
        if let url = InstagramFetcher.firstURL(in: pasted) {
            link = url.absoluteString
            let remainder = pasted.replacingOccurrences(of: url.absoluteString, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.count > 20 { text = remainder }
        } else {
            text = pasted
        }
    }

    private func runImport() {
        working = true
        status = nil
        Task {
            var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if source.isEmpty, let url = URL(string: link.trimmingCharacters(in: .whitespaces)) {
                status = "Fetching the caption…"
                if let caption = await InstagramFetcher.caption(for: url) {
                    source = caption
                    text = caption
                } else {
                    status = "Couldn't read the caption from Instagram. Copy the caption and paste it in step 2."
                    working = false
                    return
                }
            }
            do {
                status = "Reading the recipe…"
                let result = try await RecipeAI.parseRecipe(from: source)
                parsed = result
                status = "Check it below, then tap Save."
            } catch {
                status = error.localizedDescription
            }
            working = false
        }
    }

    private func save() {
        guard let parsed else { return }
        let recipe = Recipe(name: parsed.name,
                            servings: max(1, Int((parsed.servings ?? 1).rounded())),
                            slot: slot,
                            note: parsed.note ?? "",
                            ingredients: parsed.ingredients.joined(separator: "\n"))
        recipe.stepsRaw = parsed.steps.joined(separator: "\n")
        recipe.caloriesPerServing = parsed.calories.map { Int($0.rounded()) }
        recipe.proteinPerServing = parsed.protein.map { Int($0.rounded()) }
        recipe.carbsPerServing = parsed.carbs.map { Int($0.rounded()) }
        recipe.fatPerServing = parsed.fat.map { Int($0.rounded()) }
        recipe.sourceURL = link.trimmingCharacters(in: .whitespaces)
        context.insert(recipe)
        dismiss()
    }
}
