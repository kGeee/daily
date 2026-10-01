import SwiftUI
import AVFoundation
import UserNotifications

/// Full-screen, one-step-at-a-time cooking mode. Keeps the screen awake,
/// can read steps aloud, and offers timers for any time mentioned in a step.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    @State private var index = 0
    @State private var readAloud = false
    @State private var showIngredients = false
    @State private var timers: [CookTimer] = []
    @State private var synthesizer = AVSpeechSynthesizer()

    private var steps: [String] { recipe.steps }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                if steps.isEmpty {
                    Spacer()
                    Text("This recipe has no steps yet. Edit it to add them, one per line.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.muted)
                        .padding(32)
                    Spacer()
                } else {
                    if !timers.isEmpty { timerStrip }
                    TabView(selection: $index) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            stepPage(number: i, text: step)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    controls
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showIngredients = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Ingredients")
                    Button {
                        readAloud.toggle()
                        if readAloud { speak(index) } else { synthesizer.stopSpeaking(at: .immediate) }
                    } label: {
                        Image(systemName: readAloud ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel(readAloud ? "Stop reading aloud" : "Read steps aloud")
                }
            }
            .sheet(isPresented: $showIngredients) {
                NavigationStack {
                    List(recipe.ingredients, id: \.self) { Text($0) }
                        .navigationTitle("Ingredients")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showIngredients = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            synthesizer.stopSpeaking(at: .immediate)
        }
        .onChange(of: index) { _, newValue in
            if readAloud { speak(newValue) }
        }
    }

    // MARK: Pieces

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.food)
                .frame(width: steps.isEmpty ? 0 : geo.size.width * CGFloat(index + 1) / CGFloat(steps.count))
                .animation(.easeOut, value: index)
        }
        .frame(height: 4)
        .background(Palette.idle)
    }

    private func stepPage(number: Int, text: String) -> some View {
        let mentioned = ingredientsMentioned(in: text)
        let durations = CookTimer.durations(in: text)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionLabel(text: "Step \(number + 1) of \(steps.count)", color: Palette.foodText)
                Text(text)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !durations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(durations, id: \.self) { seconds in
                            Button {
                                startTimer(seconds: seconds, step: number)
                            } label: {
                                Label("Start \(CookTimer.label(seconds)) timer", systemImage: "timer")
                                    .font(.headline)
                                    .foregroundStyle(Palette.onAccent)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                    .background(Palette.food, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !mentioned.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "You'll need")
                        ForEach(mentioned, id: \.self) { line in
                            Text("• " + line)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .card(fill: Palette.card)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Text("Back")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.4 : 1)

            Button {
                if index >= steps.count - 1 {
                    dismiss()
                } else {
                    withAnimation { index += 1 }
                }
            } label: {
                Text(index >= steps.count - 1 ? "Done" : "Next")
                    .font(.headline)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Palette.food, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var timerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timers) { timer in
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                        if timer.end > Date() {
                            Text(timer.end, style: .timer)
                                .monospacedDigit()
                        } else {
                            Text("Done")
                        }
                        Text("· step \(timer.step + 1)")
                            .foregroundStyle(Palette.muted)
                        Button {
                            cancel(timer)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel timer")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Palette.foodTint, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Helpers

    private func ingredientsMentioned(in step: String) -> [String] {
        let lower = step.lowercased()
        return recipe.ingredients.filter { line in
            let name = GroceryParser.parse(line).name.lowercased()
            let keyWord = name.split(separator: " ").last.map(String.init) ?? name
            return keyWord.count > 2 && lower.contains(keyWord)
        }
    }

    private func speak(_ i: Int) {
        guard steps.indices.contains(i) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Step \(i + 1). " + steps[i])
        synthesizer.speak(utterance)
    }

    private func startTimer(seconds: Int, step: Int) {
        let timer = CookTimer(step: step, seconds: seconds)
        timers.append(timer)

        let content = UNMutableNotificationContent()
        content.title = "Timer done · \(recipe.name)"
        content.body = "Step \(step + 1): " + (steps.indices.contains(step) ? steps[step] : "")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "cook-" + timer.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false))
        Task {
            _ = await Reminders.requestPermission()
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["cook-" + timer.id.uuidString])
    }
}

struct CookTimer: Identifiable {
    let id = UUID()
    let step: Int
    let end: Date

    init(step: Int, seconds: Int) {
        self.step = step
        self.end = Date().addingTimeInterval(TimeInterval(seconds))
    }

    /// Finds times like "10 minutes", "5-7 min", "1 hour", "30 sec" in a step. Uses the upper end of a range.
    static func durations(in text: String) -> [Int] {
        let pattern = "(\\d+)\\s*(?:-|–|to)?\\s*(\\d+)?\\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        var result: [Int] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let first = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let second = match.range(at: 2).location != NSNotFound ? Int(ns.substring(with: match.range(at: 2))) : nil
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            let amount = second ?? first
            let multiplier = unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("s") ? 1 : 60)
            let seconds = amount * multiplier
            if seconds > 0, !result.contains(seconds) { result.append(seconds) }
        }
        return result
    }

    static func label(_ seconds: Int) -> String {
        if seconds % 3600 == 0 { return "\(seconds / 3600) hr" }
        if seconds >= 60 { return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds) sec"
    }
}
