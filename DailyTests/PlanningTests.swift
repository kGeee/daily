import XCTest
import SwiftData
@testable import Daily

final class CustomEventTests: XCTestCase {
    private func event(_ repeats: EventRepeat) -> CustomEvent {
        CustomEvent(title: "Call", start: day(0, hour: 18), durationMinutes: 30, kind: .general, repeats: repeats, remind: false)
    }

    func testOneOff() {
        let e = event(.none)
        XCTAssertTrue(e.occurs(on: day(0)))
        XCTAssertFalse(e.occurs(on: day(1)))
    }

    func testWeekdaysSkipsWeekend() {
        let e = event(.weekdays)
        XCTAssertTrue(e.occurs(on: day(4)))
        XCTAssertFalse(e.occurs(on: day(5)))
    }

    func testWeeklyAndNeverBeforeStart() {
        let e = event(.weekly)
        XCTAssertTrue(e.occurs(on: day(7)))
        XCTAssertFalse(e.occurs(on: day(3)))
        XCTAssertFalse(e.occurs(on: day(-7)))
    }

    func testBlockUsesThatDaysDate() {
        let block = event(.daily).block(on: day(2))
        XCTAssertEqual(block.start, ClockTime(18, 0).on(day(2)))
        XCTAssertEqual(block.end, ClockTime(18, 30).on(day(2)))
        XCTAssertNotNil(block.eventID)
    }

    func testEventsAppearOnTimeline() {
        let planner = DayPlanner(pattern: MySchedule.defaultPattern, overrides: [])
        let blocks = planner.blocks(for: day(0), lunchNote: nil, dinnerNote: nil, events: [event(.none)])
        XCTAssertTrue(blocks.contains { $0.title == "Call" })
    }
}

final class GymRotationTests: XCTestCase {
    private func templates() -> [WorkoutTemplate] {
        WorkoutTemplate.starters.enumerated().map {
            WorkoutTemplate(name: $0.element.name, order: $0.offset, exercises: $0.element.exercises, isCardio: $0.element.isCardio)
        }
    }

    func testStartsWithFirstTemplate() {
        XCTAssertEqual(WorkoutTemplate.nextName(templates: templates(), sessions: []), "Back")
    }

    func testRotatesAfterLastFinishedWorkoutAndSkipsCardio() {
        let back = WorkoutSession(templateName: "Back", exercises: [])
        back.finishedAt = Date()
        XCTAssertEqual(WorkoutTemplate.nextName(templates: templates(), sessions: [back]), "Chest")

        let legs = WorkoutSession(templateName: "Legs", exercises: [])
        legs.date = Date().addingTimeInterval(60)
        legs.finishedAt = Date().addingTimeInterval(3600)
        XCTAssertEqual(WorkoutTemplate.nextName(templates: templates(), sessions: [back, legs]), "Back")
    }

    func testUnfinishedWorkoutDoesNotCount() {
        let inProgress = WorkoutSession(templateName: "Chest", exercises: [])
        XCTAssertEqual(WorkoutTemplate.nextName(templates: templates(), sessions: [inProgress]), "Back")
    }
}

@MainActor
final class BackupTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: FoodEntry.self, GroceryItem.self, Recipe.self, WaterEntry.self, BlockCheck.self,
                           DayTypeOverride.self, CustomEvent.self, MealPlan.self, WorkoutTemplate.self,
                           WorkoutSession.self, SetLog.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testExportThenRestoreRoundTrip() throws {
        resetPrefs()
        UserDefaults.standard.set(150, forKey: Pref.proteinGoal)

        let sourceContainer = try makeContainer()
        let source = sourceContainer.mainContext
        let recipe = Recipe(name: "Turkey chili", servings: 4, slot: .dinner, ingredients: "1 lb ground turkey")
        recipe.caloriesPerServing = 430
        source.insert(recipe)
        source.insert(FoodEntry(slot: .lunch, name: "Burrito bowl", source: .prepped, calories: 520, protein: 42))
        source.insert(MealPlan(dayKey: "2026-10-05", slot: .dinner, title: "Turkey chili"))
        let session = WorkoutSession(templateName: "Back", exercises: ["Lat pulldown"])
        session.finishedAt = Date()
        source.insert(session)
        let log = SetLog(exercise: "Lat pulldown", index: 0, weight: 120, reps: 10)
        source.insert(log)
        log.session = session
        try source.save()

        let url = try Backup.export(context: source)
        UserDefaults.standard.set(100, forKey: Pref.proteinGoal)

        let targetContainer = try makeContainer()
        let target = targetContainer.mainContext
        target.insert(FoodEntry(slot: .snack, name: "Should be replaced", source: .cooked))
        try target.save()
        _ = try Backup.restore(from: url, context: target)

        let recipes = try target.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.map { $0.name }, ["Turkey chili"])
        XCTAssertEqual(recipes.first?.caloriesPerServing, 430)
        XCTAssertEqual(try target.fetch(FetchDescriptor<FoodEntry>()).map { $0.name }, ["Burrito bowl"])
        XCTAssertEqual(try target.fetch(FetchDescriptor<MealPlan>()).count, 1)
        let sessions = try target.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.first?.allSets.first?.weight, 120)
        XCTAssertEqual(MySchedule.proteinGoal, 150, "Settings come back too")
        resetPrefs()
    }
}
