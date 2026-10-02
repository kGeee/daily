# Sharing Daily with TestFlight

TestFlight lets you (and friends) install Daily from Apple's TestFlight app instead of
re-running it from Xcode every 7 days. Builds last 90 days.

## 1. Join the Apple Developer Program (once)

- Go to https://developer.apple.com/programs/enroll and enroll with your Apple ID ($99/year).
  Approval usually takes a few hours to 2 days.
- When it's active, Xcode shows a new team (your name, not "Personal Team") under
  Xcode → Settings → Accounts.

## 2. Point the project at the paid team

In Xcode, for **each** target (Daily, DailyWidgets, DailyShare, DailyTests):
Signing & Capabilities → Team → pick the paid team. Keep "Automatically manage signing" on.

- Xcode registers the bundle IDs (`com.kgeee.daily`, `.widgets`, `.share`) and the App Group
  `group.com.kgeee.daily` for you. If it says an ID is taken, change `com.kgeee` to something
  unique everywhere (all targets, `SharedStore.groupID`, and `Config/*.entitlements`).
- Under Signing & Capabilities, make sure **App Groups** is listed with `group.com.kgeee.daily`
  checked for Daily, DailyWidgets and DailyShare.

## 3. Create the app in App Store Connect (once)

1. Open https://appstoreconnect.apple.com → Apps → **+** → New App.
2. Platform iOS, Name (must be unique on the App Store, e.g. "Daily – Commute & Meals"),
   language English, Bundle ID `com.kgeee.daily`, SKU anything (e.g. `daily-001`).
3. You don't need screenshots or a description for TestFlight.

## 4. Archive and upload

1. In Xcode, pick **Any iOS Device (arm64)** as the run destination.
2. Check the version and build: Daily target → General → Version `0.1`, Build `1`.
   Every upload needs a higher Build number (2, 3, …). Widgets and Share use the same numbers.
3. **Product → Archive**. When it finishes, the Organizer opens.
4. **Distribute App → TestFlight & App Store → Distribute** (or "TestFlight Internal Only").
5. Wait for the "has completed processing" email (usually 10–30 minutes).

The project already says it uses only standard encryption (HTTPS), so App Store Connect
won't ask the export-compliance question, and it includes the privacy manifest Apple requires.

## 5. Invite testers

**Just you / people on your team (no review, fastest):**
App Store Connect → your app → TestFlight → Internal Testing → **+** → create a group →
add testers (they need to be users on your App Store Connect team, up to 100) → add the build.
Each tester gets an email, installs the TestFlight app, and taps Install.

**Friends (anyone with an email or a link):**
TestFlight → External Testing → **+** → create a group → add the build.
Fill in "Test Information" (what to test, a contact email). The first build of each version goes
through a short Beta App Review (often under a day). Then turn on **Public Link** and share it,
or add testers by email (up to 10,000).

## 6. Shipping an update

Bump the Build number → Product → Archive → Distribute. Testers get it automatically in TestFlight.

## Good to know

- Each tester's data stays on their own phone. Backups (Settings → Backup) move data between phones.
- AI features and live Caltrain need each tester's own Anthropic / 511.org key in Settings.
- Widgets, the Lock Screen countdown and Share → Daily all work in TestFlight builds.
