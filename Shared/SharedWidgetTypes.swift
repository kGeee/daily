import Foundation
import ActivityKit
import AppIntents
import WidgetKit

/// The lock-screen / Dynamic Island countdown for your next departure.
struct DepartureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var departure: Date
        var leaveBy: Date
        var symbol: String
    }
}

/// "+8 oz" button on the water widget. Runs without opening the app.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Add water"
    static var description = IntentDescription("Log water in Daily.")

    @Parameter(title: "Ounces", default: 8)
    var ounces: Int

    init() {}

    init(ounces: Int) {
        self.ounces = ounces
    }

    func perform() async throws -> some IntentResult {
        SharedStore.addPendingWater(ounces)
        WidgetCenter.shared.reloadTimelines(ofKind: "Water")
        return .result()
    }
}
