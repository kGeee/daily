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

## First run with widgets and sharing

The project has three targets: **Daily**, **DailyWidgets** and **DailyShare**. For each one, open
Signing & Capabilities and pick your Team. They share data through the App Group `group.com.kgeee.daily`
(already set in `Config/*.entitlements`). If Xcode says the App Group or bundle IDs aren't available,
change `com.kgeee` to something unique in all three targets and in `SharedStore.groupID` + the entitlements.

## Tests

Press **⌘U** in Xcode (with an iPhone simulator selected) to run the unit tests in `DailyTests/`:
schedule and day-type logic, Caltrain train picking, leave-by times, events, gym rotation,
grocery parsing, cooking-timer detection, Instagram link handling, and a full backup → restore round trip.

## What's in the app

- **Today** — week strip, day type (Shuttle / Gym / Caltrain), timeline with check-offs and a "now" line,
  water (+8 oz; long-press for more), eat-outs this week.
- **Commute** — morning departure countdown, afternoon plan per day type, editable usual week.
- **Food** — log meals (Prepped / Cooked / Ate out) with optional calories and protein,
  home-vs-out count for the week, recipes, and a shopping list for two trips a week.
- **Gym** — Back / Chest / Legs / Cardio templates (editable), set logging prefilled from last time,
  cardio minutes, workout history, and a "wrap up by" banner for the Caltrain on gym days.
- **Your own events** — the + button on Today adds one-off or repeating events (daily, weekdays, weekly).
- **Reminders** — turn on in Commute: 10 min before each departure and your events, plus Sunday prep and wind-down.
- **Settings** (gear on Commute) — shuttle times and stop, walk times, gym-day timing, your Caltrain
  station and the trains you take, your daily times, goals and reminder lead time.
- **Plan the week** (calendar button on Today, or Food → Plan & groceries) — set each day's type,
  see the gym rotation and commute, pick lunches/dinners from your recipes, and send the planned
  recipes' ingredients to the grocery list.
- **Tomorrow** card on Today after 5 PM — first departure and leave-by time, gym bag, lunch, events.
- Timeline shows free gaps of 90+ minutes, leave-by times, and planned meals.
- **Recipes** — tap one for ingredients, steps and per-serving nutrition. **Start cooking** opens a
  step-by-step mode (screen stays on, read-aloud, one-tap timers for times in each step).
- **Calories & macros** — per recipe and per meal; logging a recipe fills them in. With an Anthropic API
  key (Settings → AI) the app can estimate them, and **Import** reads a recipe from an Instagram reel link
  or pasted caption.

All data stays on the phone (SwiftData). Light and dark mode follow the system setting.

## Your schedule

Change everything in the app under Commute → gear. Defaults live in `Pref` in `Daily/Schedule/Schedule.swift`.
Caltrain uses the train times you add in Settings; until then it shows estimates (marked ~).

- **Goals** — daily calories and protein (Settings), with progress on Today and Food.
- **Week in review** — Food → Review (and a banner on Sundays): eat-outs vs goal, nutrition, gym, water,
  departures, and a 6-week eating-out trend.
- **Plan my prep with AI** — in Plan the week: picks recipes that reheat well and hit your goals, fills
  empty meals, and builds the grocery list (optionally using what's already in your kitchen).
- **Live Caltrain** — add a free 511.org key and your station in Settings for live departures and delays.
- **Backup** — Settings → Backup to save everything to a file, and restore from one.
- **Widgets** — Next up (home + lock screen) and Water with +8 / +16 buttons.
- **Lock Screen countdown** — Commute → "Show countdown on Lock Screen" (Live Activity + Dynamic Island).
- **Share from Instagram** — Share → Daily on a reel; the importer opens next time you open the app.

## Next up

- Live Caltrain times (511.org API)
- Apple Health for sleep and water
- Recipe suggestions from what you have
