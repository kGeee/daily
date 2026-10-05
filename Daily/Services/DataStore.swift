import Foundation
import SwiftData

/// The app's database. Syncs through your private iCloud (CloudKit) when you're signed in to iCloud and
/// sync is on; otherwise it's the same database, kept only on this device. Both use the same file, so
/// turning sync on uploads what's already here.
enum DataStore {
    static let cloudContainerID = "iCloud.com.kgeee.daily"
    /// Settings toggle; on unless you turn it off. Takes effect the next time the app starts.
    static let syncKey = "pref.iCloudSync"

    static let modelTypes: [any PersistentModel.Type] = [
        FoodEntry.self, GroceryItem.self, Recipe.self, WaterEntry.self, BlockCheck.self, DayTypeOverride.self,
        CustomEvent.self, MealPlan.self, WorkoutTemplate.self, WorkoutSession.self, SetLog.self,
        FocusSession.self, Restaurant.self, JournalEntry.self
    ]

    enum Mode: Equatable {
        case iCloud
        case local(reason: String)
    }

    /// How this launch is storing data (shown in Settings).
    private(set) static var mode: Mode = .local(reason: "Starting")

    static var syncWanted: Bool {
        UserDefaults.standard.object(forKey: syncKey) as? Bool ?? true
    }

    static var signedInToICloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Whether to try iCloud this launch, and if not, why.
    static func plan(syncWanted: Bool, signedIn: Bool, runningTests: Bool) -> Mode {
        if runningTests { return .local(reason: "Running tests") }
        if !syncWanted { return .local(reason: "iCloud sync is off") }
        if !signedIn { return .local(reason: "Not signed in to iCloud") }
        return .iCloud
    }

    static let shared: ModelContainer = make()

    private static func make() -> ModelContainer {
        let schema = Schema(modelTypes)
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let wanted = plan(syncWanted: syncWanted, signedIn: signedInToICloud, runningTests: runningTests)

        if wanted == .iCloud {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            do {
                let container = try ModelContainer(for: schema, configurations: [cloud])
                mode = .iCloud
                return container
            } catch {
                mode = .local(reason: "iCloud isn't set up for this build")
            }
        } else {
            mode = wanted
        }

        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Couldn't open the database: \(error)")
        }
    }
}

/// Sync can't enforce "one per day" rules, so two devices editing the same day can leave duplicates.
/// This keeps one of each and deletes the rest.
enum Dedupe {
    /// The items to delete so each key appears once (the first one seen is kept).
    static func extras<T, K: Hashable>(_ items: [T], key: (T) -> K) -> [T] {
        var seen = Set<K>()
        var out: [T] = []
        for item in items {
            if seen.insert(key(item)).inserted == false { out.append(item) }
        }
        return out
    }

    @MainActor
    static func run(in context: ModelContext) {
        var removed = 0
        if let overrides = try? context.fetch(FetchDescriptor<DayTypeOverride>()) {
            for extra in extras(overrides, key: \.dayKey) { context.delete(extra); removed += 1 }
        }
        if let checks = try? context.fetch(FetchDescriptor<BlockCheck>()) {
            for extra in extras(checks, key: { $0.dayKey + "|" + $0.blockID }) { context.delete(extra); removed += 1 }
        }
        if let plans = try? context.fetch(FetchDescriptor<MealPlan>()) {
            for extra in extras(plans, key: { $0.dayKey + "|" + $0.slotRaw }) { context.delete(extra); removed += 1 }
        }
        if removed > 0 { try? context.save() }
    }
}
