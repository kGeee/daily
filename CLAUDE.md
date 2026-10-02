# Daily — notes for Claude

- SwiftUI + SwiftData iOS app, iOS 17+, Swift 5 language mode. No server.
- Xcode project uses a file-system synchronized group: any file added under `Daily/` is in the target automatically. Don't add per-file entries to `project.pbxproj`.
- Colors come only from `Palette` in `Daily/Theme/Theme.swift` (each has a light and dark value). Don't hardcode colors in views.
- The user's schedule is read through `MySchedule` (`Daily/Schedule/Schedule.swift`), backed by UserDefaults keys in `Pref` and edited in `SettingsView`. Bump `Pref.revision` after settings change. Shuttle 7:45 AM out, 4:00 PM home. Gym days: leave work 3:00 PM, gym, Caltrain home from Sunnyvale.
- This environment can't build iOS. The user builds in Xcode and pastes errors back; keep changes small and conservative.
- Targets: `Daily` (app, folders `Daily/`, `SharedCore/`, `Shared/`), `DailyWidgets` (widgets + Live Activity, folders `DailyWidgets/`, `SharedCore/`, `Shared/`), `DailyShare` (share extension, folders `DailyShare/`, `SharedCore/`). `SharedCore` must stay free of WidgetKit/ActivityKit. Extension Info.plists and entitlements live in `Config/` (not a synced folder).
- App, widgets and share extension talk through the App Group `group.com.kgeee.daily` (`SharedStore`). The app pushes a snapshot for widgets via `WidgetSync`.
- AI calls go through `AIClient` (Anthropic API, user's key in Keychain). Live trains use 511.org (`Caltrain511`).
- Unit tests live in `DailyTests/` (target `DailyTests`, host app `Daily`, shared scheme `Daily`). Add a test with any logic change; keep logic out of views where possible so it can be tested.
- Commute timelines come from `Routines` (`Daily/Schedule/Routines.swift`): per-DayType lists of `RoutineStep`, resolved by `RoutineResolver` with `Timetables` and one-day `StepOverride`s. Default routines are built from the old `Pref` values. Built-in step ids ("out", "work", "go", "gym", "home") are relied on by check-offs and tests.
- Signing team is `7CK43PG7GZ` (set in the project generator for every target).
