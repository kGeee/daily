import XCTest
@testable import Daily

final class PhotoEstimateTests: XCTestCase {
    func testTextOnlyContentIsPlainString() {
        XCTAssertEqual(AIClient.messageContent(prompt: "hi", images: []) as? String, "hi")
    }

    func testImageGoesBeforeText() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        let blocks = try XCTUnwrap(AIClient.messageContent(prompt: "what is this", images: [jpeg]) as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = try XCTUnwrap(blocks[0]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, jpeg.base64EncodedString())
        XCTAssertEqual(blocks[1]["text"] as? String, "what is this")
    }

    func testPhotoPromptUsesDescriptionAndPlace() {
        let p = RecipeAI.mealPrompt(description: "carne asada burrito", hasPhoto: true, place: "La Taqueria")
        XCTAssertTrue(p.contains("photo"))
        XCTAssertTrue(p.contains("carne asada burrito"))
        XCTAssertTrue(p.contains("La Taqueria"))
        XCTAssertFalse(p.contains("short name"))
    }

    func testPhotoOnlyAsksForName() {
        let p = RecipeAI.mealPrompt(description: "", hasPhoto: true, place: nil)
        XCTAssertTrue(p.contains("short name"))
        XCTAssertFalse(p.contains("Meal:"))
    }

    func testTextPromptUnchangedInSpirit() {
        let p = RecipeAI.mealPrompt(description: "Chipotle bowl", hasPhoto: false, place: nil)
        XCTAssertTrue(p.contains("Meal: Chipotle bowl"))
        XCTAssertTrue(p.contains("typical portion"))
    }
}
