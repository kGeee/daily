import XCTest
@testable import Daily

final class GroceryParserTests: XCTestCase {
    func testQuantityUnitAndSection() {
        let item = GroceryParser.parse("2 lb chicken thighs")
        XCTAssertEqual(item.name, "Chicken thighs")
        XCTAssertEqual(item.quantity, "2 lb")
        XCTAssertEqual(item.section, "Protein")
    }

    func testCountWithoutUnit() {
        let item = GroceryParser.parse("3 limes")
        XCTAssertEqual(item.name, "Limes")
        XCTAssertEqual(item.quantity, "3")
        XCTAssertEqual(item.section, "Produce")
    }

    func testNoQuantityFallsBackToPantry() {
        let item = GroceryParser.parse("olive oil")
        XCTAssertEqual(item.quantity, "")
        XCTAssertEqual(item.section, "Pantry")
    }

    func testDairyAndFrozen() {
        XCTAssertEqual(GroceryParser.section(for: "Greek yogurt"), "Dairy")
        XCTAssertEqual(GroceryParser.section(for: "Frozen peas"), "Frozen")
    }
}

final class CookTimerTests: XCTestCase {
    func testFindsMinutes() {
        XCTAssertEqual(CookTimer.durations(in: "Simmer for 10 minutes, stirring."), [600])
    }

    func testRangeUsesUpperEndAndKeepsOrder() {
        XCTAssertEqual(CookTimer.durations(in: "Sear 5-6 minutes per side, then rest 5 min."), [360, 300])
    }

    func testHoursAndSeconds() {
        XCTAssertEqual(CookTimer.durations(in: "Bake 1 hour"), [3600])
        XCTAssertEqual(CookTimer.durations(in: "Microwave 90 seconds"), [90])
    }

    func testNoTimes() {
        XCTAssertEqual(CookTimer.durations(in: "Season with salt and 2 cloves of garlic."), [])
    }

    func testLabels() {
        XCTAssertEqual(CookTimer.label(600), "10 min")
        XCTAssertEqual(CookTimer.label(3600), "1 hr")
        XCTAssertEqual(CookTimer.label(90), "1m 30s")
        XCTAssertEqual(CookTimer.label(45), "45 sec")
    }
}

final class RecipeTests: XCTestCase {
    func testIngredientsAndStepsSkipBlankLines() {
        let recipe = Recipe(name: "Chili", servings: 4, slot: .dinner, ingredients: "1 lb turkey\n\n  1 can beans  \n")
        recipe.stepsRaw = "Brown the turkey\n\nSimmer 20 minutes"
        XCTAssertEqual(recipe.ingredients, ["1 lb turkey", "1 can beans"])
        XCTAssertEqual(recipe.steps.count, 2)
    }

    func testMacroLine() {
        let recipe = Recipe(name: "Bowl", servings: 4, slot: .lunch)
        XCTAssertNil(recipe.macroLine)
        recipe.caloriesPerServing = 520
        recipe.proteinPerServing = 42
        recipe.carbsPerServing = 48
        recipe.fatPerServing = 16
        XCTAssertEqual(recipe.macroLine, "520 cal · 42P 48C 16F")
    }
}

final class InstagramTests: XCTestCase {
    func testShortcode() {
        XCTAssertEqual(InstagramFetcher.shortcode(in: URL(string: "https://www.instagram.com/reel/C9xK2abc/?igsh=xyz")!), "C9xK2abc")
        XCTAssertEqual(InstagramFetcher.shortcode(in: URL(string: "https://instagram.com/p/AbC123/")!), "AbC123")
        XCTAssertNil(InstagramFetcher.shortcode(in: URL(string: "https://instagram.com/someuser/")!))
    }

    func testFindsLinkInSharedText() {
        let text = "Check this out https://www.instagram.com/reel/C9xK2abc/ so good"
        XCTAssertEqual(InstagramFetcher.firstURL(in: text)?.absoluteString, "https://www.instagram.com/reel/C9xK2abc/")
    }
}
