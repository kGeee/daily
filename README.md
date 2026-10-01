# Daily

A personal iOS app that puts commute, work, gym, food, sleep and water on one daily timeline.

Design mockups: the "Daily Life App Mockups" canvas (light + dark).

## Run it

1. Open `Daily.xcodeproj` in Xcode (16 or newer).
2. Select the **Daily** target → **Signing & Capabilities** → choose your Team (your Apple ID works).
   If Xcode says the bundle ID is taken, change `com.kgeee.daily` to something unique.
3. Pick an iPhone simulator or your plugged-in iPhone and press **Run** (⌘R).

On a real iPhone the first time: Settings → Privacy & Security → Developer Mode → On,
and Settings → General → VPN & Device Management → trust your developer certificate.

## What's in v0.1

- **Today** — week strip, day type (Shuttle / Gym / Caltrain), timeline with check-offs and a "now" line,
  water (+8 oz; long-press for more), eat-outs this week.
- **Commute** — morning departure countdown, afternoon plan per day type, editable usual week.
- **Food** — log meals (Prepped / Cooked / Ate out) with optional calories and protein,
  home-vs-out count for the week, recipes, and a shopping list for two trips a week.
- **Gym** — placeholder.

All data stays on the phone (SwiftData). Light and dark mode follow the system setting.

## Your schedule

Times live in `Daily/Schedule/Schedule.swift` (`MySchedule`). Caltrain times are estimates for now.

## Next up

- Gym templates and set logging
- Notifications before departures
- Live Caltrain times (511.org API)
- Apple Health for sleep and water
- Recipe suggestions from what you have
