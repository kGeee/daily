import SwiftUI
import SwiftData

@main
struct DailyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            FoodEntry.self,
            GroceryItem.self,
            Recipe.self,
            WaterEntry.self,
            BlockCheck.self,
            DayTypeOverride.self
        ])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "clock") }
            CommuteView()
                .tabItem { Label("Commute", systemImage: "bus") }
            GymView()
                .tabItem { Label("Gym", systemImage: "dumbbell") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
        }
        .tint(Palette.commute)
    }
}
