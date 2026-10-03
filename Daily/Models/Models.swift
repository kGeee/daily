import Foundation
import SwiftData

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MealSource: String, CaseIterable, Identifiable {
    case prepped, cooked, out
    var id: String { rawValue }
    var title: String {
        switch self {
        case .prepped: return "Prepped"
        case .cooked: return "Cooked"
        case .out: return "Ate out"
        }
    }
    var isHome: Bool { self != .out }
}

@Model
final class FoodEntry {
    var date: Date
    var slotRaw: String
    var name: String
    var sourceRaw: String
    var calories: Int?
    var protein: Int?
    var carbs: Int? = nil
    var fat: Int? = nil
    /// Set for meals eaten out at a saved restaurant (these are its visits).
    var restaurantID: UUID? = nil

    init(date: Date = .now, slot: MealSlot, name: String, source: MealSource,
         calories: Int? = nil, protein: Int? = nil, carbs: Int? = nil, fat: Int? = nil) {
        self.date = date
        self.slotRaw = slot.rawValue
        self.name = name
        self.sourceRaw = source.rawValue
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .snack }
    var source: MealSource { MealSource(rawValue: sourceRaw) ?? .cooked }
}

@Model
final class GroceryItem {
    var name: String
    var quantity: String
    var section: String
    var trip: Int
    var isDone: Bool
    var createdAt: Date

    init(name: String, quantity: String = "", section: String, trip: Int) {
        self.name = name
        self.quantity = quantity
        self.section = section
        self.trip = trip
        self.isDone = false
        self.createdAt = .now
    }
}

@Model
final class Recipe {
    var name: String
    var servings: Int
    var slotRaw: String
    var note: String
    var createdAt: Date
    /// One ingredient per line, e.g. "2 lb chicken thighs".
    var ingredientsRaw: String = ""
    /// One step per line.
    var stepsRaw: String = ""
    var caloriesPerServing: Int? = nil
    var proteinPerServing: Int? = nil
    var carbsPerServing: Int? = nil
    var fatPerServing: Int? = nil
    /// Where it came from, e.g. an Instagram reel link.
    var sourceURL: String = ""
    /// What `servings` counts, e.g. "nuggets" for a recipe that makes 30 nuggets. Empty = servings.
    /// Nutrition is per one of these.
    var yieldUnit: String = ""
    /// How many of those make one meal (e.g. 6 nuggets).
    var unitsPerMeal: Double = 1

    init(name: String, servings: Int, slot: MealSlot, note: String = "", ingredients: String = "") {
        self.name = name
        self.servings = servings
        self.slotRaw = slot.rawValue
        self.note = note
        self.createdAt = .now
        self.ingredientsRaw = ingredients
    }

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .dinner }

    var ingredients: [String] {
        ingredientsRaw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var steps: [String] {
        stepsRaw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasNutrition: Bool { caloriesPerServing != nil }

    var hasCustomUnit: Bool { !yieldUnit.trimmingCharacters(in: .whitespaces).isEmpty }

    /// "nuggets" / "servings" (or the singular for exactly one).
    func unitLabel(for amount: Double) -> String {
        let unit = yieldUnit.trimmingCharacters(in: .whitespaces)
        if unit.isEmpty { return amount == 1 ? "serving" : "servings" }
        if amount == 1, unit.count > 3, unit.hasSuffix("s") { return String(unit.dropLast()) }
        return unit
    }

    /// How many meals the whole recipe covers.
    var mealCount: Int {
        max(1, Int((Double(servings) / max(unitsPerMeal, 0.1)).rounded(.down)))
    }

    /// Nutrition for eating `amount` units (servings, nuggets…).
    func nutrition(for amount: Double) -> (calories: Int?, protein: Int?, carbs: Int?, fat: Int?) {
        func scale(_ value: Int?) -> Int? { value.map { Int((Double($0) * amount).rounded()) } }
        return (scale(caloriesPerServing), scale(proteinPerServing), scale(carbsPerServing), scale(fatPerServing))
    }

    /// "8 nuggets", "1.5 servings".
    func amountLabel(_ amount: Double) -> String {
        let number = amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount)
        return number + " " + unitLabel(for: amount)
    }

    /// "520 cal · 42P 48C 16F", or nil if unknown.
    var macroLine: String? {
        guard let cal = caloriesPerServing else { return nil }
        var parts = ["\(cal) cal"]
        let macros = [("P", proteinPerServing), ("C", carbsPerServing), ("F", fatPerServing)]
            .compactMap { pair in pair.1.map { "\($0)\(pair.0)" } }
        if !macros.isEmpty { parts.append(macros.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }
}

/// What you plan to eat for a meal on a given day (a recipe name, or "Eat out").
@Model
final class MealPlan {
    var dayKey: String
    var slotRaw: String
    var title: String

    init(dayKey: String, slot: MealSlot, title: String) {
        self.dayKey = dayKey
        self.slotRaw = slot.rawValue
        self.title = title
    }

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .dinner }
    var isEatingOut: Bool { title == MealPlan.eatOut }

    static let eatOut = "Eat out"
}

@Model
final class WaterEntry {
    var date: Date
    var ounces: Int

    init(date: Date = .now, ounces: Int) {
        self.date = date
        self.ounces = ounces
    }
}

/// Marks a timeline block as done on a given day.
@Model
final class BlockCheck {
    var dayKey: String
    var blockID: String

    init(dayKey: String, blockID: String) {
        self.dayKey = dayKey
        self.blockID = blockID
    }
}

/// A one-off change to a day's type (e.g. making today a gym day).
@Model
final class DayTypeOverride {
    @Attribute(.unique) var dayKey: String
    var typeRaw: String

    init(dayKey: String, typeRaw: String) {
        self.dayKey = dayKey
        self.typeRaw = typeRaw
    }
}
