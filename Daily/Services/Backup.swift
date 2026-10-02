import Foundation
import SwiftData

/// Exports everything (data + settings) to one JSON file and restores it.
enum Backup {
    struct File: Codable {
        var version = 1
        var exportedAt = Date()
        var intPrefs: [String: Int] = [:]
        var stringPrefs: [String: String] = [:]
        var boolPrefs: [String: Bool] = [:]
        /// Routines, timetables and one-day changes (optional so older backups still load).
        var dataPrefs: [String: Data]? = nil
        var food: [FoodDTO] = []
        var groceries: [GroceryDTO] = []
        var recipes: [RecipeDTO] = []
        var plans: [PlanDTO] = []
        var water: [WaterDTO] = []
        var checks: [CheckDTO] = []
        var overrides: [OverrideDTO] = []
        var events: [EventDTO] = []
        var templates: [TemplateDTO] = []
        var sessions: [SessionDTO] = []
    }

    struct FoodDTO: Codable { var date: Date; var slot: String; var name: String; var source: String; var calories, protein, carbs, fat: Int? }
    struct GroceryDTO: Codable { var name, quantity, section: String; var trip: Int; var isDone: Bool; var createdAt: Date }
    struct RecipeDTO: Codable {
        var name: String; var servings: Int; var slot: String; var note: String; var createdAt: Date
        var ingredients: String; var steps: String; var calories, protein, carbs, fat: Int?; var sourceURL: String
    }
    struct PlanDTO: Codable { var dayKey, slot, title: String }
    struct WaterDTO: Codable { var date: Date; var ounces: Int }
    struct CheckDTO: Codable { var dayKey, blockID: String }
    struct OverrideDTO: Codable { var dayKey, type: String }
    struct EventDTO: Codable { var id: UUID; var title, note: String; var start: Date; var duration: Int; var kind, repeats: String; var remind: Bool }
    struct TemplateDTO: Codable { var name: String; var order: Int; var exercises: String; var isCardio: Bool }
    struct SetDTO: Codable { var exercise: String; var index: Int; var weight: Double; var reps: Int; var isDone: Bool; var date: Date }
    struct SessionDTO: Codable {
        var date: Date; var templateName, exercises: String; var finishedAt: Date?
        var cardioMinutes: Int; var cardioNote: String; var sets: [SetDTO]
    }

    static let intKeys = [Pref.wake, Pref.workStart, Pref.lunch, Pref.dinner, Pref.windDown, Pref.bedtime,
                          Pref.shuttleOut, Pref.shuttleHome, Pref.walkToStop, Pref.leaveForGym, Pref.gymTravel,
                          Pref.workoutLength, Pref.gymToStation, Pref.walkToStation, Pref.caltrainRide, Pref.lastMile,
                          Pref.caltrainLeaveWork, Pref.prepStart, Pref.prepEnd, Pref.reminderLead, Pref.waterGoal,
                          Pref.eatOutGoal, Pref.calorieGoal, Pref.proteinGoal]
    static let stringKeys = [Pref.shuttleStop, Pref.homeStation, Pref.morningTrains, Pref.eveningTrains,
                             Pref.liveStationName, Pref.liveHomeStops, Pref.liveSunnyvaleStops, Pref.liveMountainViewStops,
                             Pref.directionToWork, "weekPattern"]
    static let dataKeys = ["pref.routines", "pref.timetableList", "pref.stepOverrides"]

    /// Times for every timetable (the built-in Caltrain ones are already in stringKeys).
    static var timetableKeys: [String] {
        Timetables.all.map { Timetables.timesKey($0.id) }.filter { !stringKeys.contains($0) }
    }
    static let boolKeys = ["remindersOn"]

    @MainActor
    static func export(context: ModelContext) throws -> URL {
        var file = File()
        let defaults = UserDefaults.standard
        for key in intKeys { if let v = defaults.object(forKey: key) as? Int { file.intPrefs[key] = v } }
        for key in stringKeys { if let v = defaults.string(forKey: key) { file.stringPrefs[key] = v } }
        for key in boolKeys { if defaults.object(forKey: key) != nil { file.boolPrefs[key] = defaults.bool(forKey: key) } }
        for key in timetableKeys { if let v = defaults.string(forKey: key) { file.stringPrefs[key] = v } }
        var dataPrefs: [String: Data] = [:]
        for key in dataKeys { if let v = defaults.data(forKey: key) { dataPrefs[key] = v } }
        file.dataPrefs = dataPrefs

        file.food = try context.fetch(FetchDescriptor<FoodEntry>()).map {
            FoodDTO(date: $0.date, slot: $0.slotRaw, name: $0.name, source: $0.sourceRaw,
                    calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
        }
        file.groceries = try context.fetch(FetchDescriptor<GroceryItem>()).map {
            GroceryDTO(name: $0.name, quantity: $0.quantity, section: $0.section, trip: $0.trip, isDone: $0.isDone, createdAt: $0.createdAt)
        }
        file.recipes = try context.fetch(FetchDescriptor<Recipe>()).map {
            RecipeDTO(name: $0.name, servings: $0.servings, slot: $0.slotRaw, note: $0.note, createdAt: $0.createdAt,
                      ingredients: $0.ingredientsRaw, steps: $0.stepsRaw, calories: $0.caloriesPerServing,
                      protein: $0.proteinPerServing, carbs: $0.carbsPerServing, fat: $0.fatPerServing, sourceURL: $0.sourceURL)
        }
        file.plans = try context.fetch(FetchDescriptor<MealPlan>()).map { PlanDTO(dayKey: $0.dayKey, slot: $0.slotRaw, title: $0.title) }
        file.water = try context.fetch(FetchDescriptor<WaterEntry>()).map { WaterDTO(date: $0.date, ounces: $0.ounces) }
        file.checks = try context.fetch(FetchDescriptor<BlockCheck>()).map { CheckDTO(dayKey: $0.dayKey, blockID: $0.blockID) }
        file.overrides = try context.fetch(FetchDescriptor<DayTypeOverride>()).map { OverrideDTO(dayKey: $0.dayKey, type: $0.typeRaw) }
        file.events = try context.fetch(FetchDescriptor<CustomEvent>()).map {
            EventDTO(id: $0.id, title: $0.title, note: $0.note, start: $0.start, duration: $0.durationMinutes,
                     kind: $0.kindRaw, repeats: $0.repeatRaw, remind: $0.remind)
        }
        file.templates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).map {
            TemplateDTO(name: $0.name, order: $0.order, exercises: $0.exercisesRaw, isCardio: $0.isCardio)
        }
        file.sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
            SessionDTO(date: s.date, templateName: s.templateName, exercises: s.exercisesRaw, finishedAt: s.finishedAt,
                       cardioMinutes: s.cardioMinutes, cardioNote: s.cardioNote,
                       sets: s.sets.map { SetDTO(exercise: $0.exercise, index: $0.index, weight: $0.weight,
                                                 reps: $0.reps, isDone: $0.isDone, date: $0.date) })
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        let name = "Daily backup " + DayKey.of(Date()) + ".json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Replaces all current data and settings with the backup's.
    @MainActor
    static func restore(from url: URL, context: ModelContext) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)

        try context.delete(model: FoodEntry.self)
        try context.delete(model: GroceryItem.self)
        try context.delete(model: Recipe.self)
        try context.delete(model: MealPlan.self)
        try context.delete(model: WaterEntry.self)
        try context.delete(model: BlockCheck.self)
        try context.delete(model: DayTypeOverride.self)
        try context.delete(model: CustomEvent.self)
        try context.delete(model: SetLog.self)
        try context.delete(model: WorkoutSession.self)
        try context.delete(model: WorkoutTemplate.self)

        let defaults = UserDefaults.standard
        for (k, v) in file.intPrefs { defaults.set(v, forKey: k) }
        for (k, v) in file.stringPrefs { defaults.set(v, forKey: k) }
        for (k, v) in file.boolPrefs { defaults.set(v, forKey: k) }
        for (k, v) in file.dataPrefs ?? [:] { defaults.set(v, forKey: k) }

        for f in file.food {
            context.insert(FoodEntry(date: f.date, slot: MealSlot(rawValue: f.slot) ?? .snack, name: f.name,
                                     source: MealSource(rawValue: f.source) ?? .cooked,
                                     calories: f.calories, protein: f.protein, carbs: f.carbs, fat: f.fat))
        }
        for g in file.groceries {
            let item = GroceryItem(name: g.name, quantity: g.quantity, section: g.section, trip: g.trip)
            item.isDone = g.isDone
            item.createdAt = g.createdAt
            context.insert(item)
        }
        for r in file.recipes {
            let recipe = Recipe(name: r.name, servings: r.servings, slot: MealSlot(rawValue: r.slot) ?? .dinner,
                                note: r.note, ingredients: r.ingredients)
            recipe.createdAt = r.createdAt
            recipe.stepsRaw = r.steps
            recipe.caloriesPerServing = r.calories
            recipe.proteinPerServing = r.protein
            recipe.carbsPerServing = r.carbs
            recipe.fatPerServing = r.fat
            recipe.sourceURL = r.sourceURL
            context.insert(recipe)
        }
        for p in file.plans { context.insert(MealPlan(dayKey: p.dayKey, slot: MealSlot(rawValue: p.slot) ?? .dinner, title: p.title)) }
        for w in file.water { context.insert(WaterEntry(date: w.date, ounces: w.ounces)) }
        for c in file.checks { context.insert(BlockCheck(dayKey: c.dayKey, blockID: c.blockID)) }
        for o in file.overrides { context.insert(DayTypeOverride(dayKey: o.dayKey, typeRaw: o.type)) }
        for e in file.events {
            let event = CustomEvent(title: e.title, note: e.note, start: e.start, durationMinutes: e.duration,
                                    kind: EventKind(rawValue: e.kind) ?? .general,
                                    repeats: EventRepeat(rawValue: e.repeats) ?? .none, remind: e.remind)
            event.id = e.id
            context.insert(event)
        }
        for t in file.templates {
            let template = WorkoutTemplate(name: t.name, order: t.order, exercises: [], isCardio: t.isCardio)
            template.exercisesRaw = t.exercises
            context.insert(template)
        }
        for s in file.sessions {
            let session = WorkoutSession(templateName: s.templateName, exercises: [])
            session.date = s.date
            session.exercisesRaw = s.exercises
            session.finishedAt = s.finishedAt
            session.cardioMinutes = s.cardioMinutes
            session.cardioNote = s.cardioNote
            context.insert(session)
            for entry in s.sets {
                let log = SetLog(exercise: entry.exercise, index: entry.index, weight: entry.weight, reps: entry.reps)
                log.isDone = entry.isDone
                log.date = entry.date
                context.insert(log)
                log.session = session
            }
        }
        try context.save()
        defaults.set(defaults.integer(forKey: Pref.revision) + 1, forKey: Pref.revision)
        return file.food.count + file.recipes.count + file.sessions.count + file.events.count
    }
}
