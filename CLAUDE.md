# Daily — notes for Claude

- SwiftUI + SwiftData iOS app, iOS 17+, Swift 5 language mode. No server.
- Xcode project uses a file-system synchronized group: any file added under `Daily/` is in the target automatically. Don't add per-file entries to `project.pbxproj`.
- Colors come only from `Palette` in `Daily/Theme/Theme.swift` (each has a light and dark value). Don't hardcode colors in views.
- The user's schedule is read through `MySchedule` (`Daily/Schedule/Schedule.swift`), backed by UserDefaults keys in `Pref` and edited in `SettingsView`. Bump `Pref.revision` after settings change. Shuttle 7:45 AM out, 4:00 PM home. Gym days: leave work 3:00 PM, gym, Caltrain home from Sunnyvale.
- This environment can't build iOS. The user builds in Xcode and pastes errors back; keep changes small and conservative.
