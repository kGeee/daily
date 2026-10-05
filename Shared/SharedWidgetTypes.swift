import Foundation
#if os(iOS)
import ActivityKit
#endif
import AppIntents
import WidgetKit

#if os(iOS)
/// The lock-screen / Dynamic Island countdown for your next departure (iPhone only).
struct DepartureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var departure: Date
        var leaveBy: Date
        var symbol: String
    }
}
#endif

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

/// Check circle on the timeline widget.
struct ToggleBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        SharedStore.togglePendingCheck(itemID)
        WidgetCenter.shared.reloadTimelines(ofKind: "Timeline")
        return .result()
    }
}

/// "+" on the timeline widget: opens the app straight to a new event.
struct AddEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Add event"
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.requestAddEvent()
        return .result()
    }
}
