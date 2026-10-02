import SwiftUI

/// "Now" at the top of Today: what you're doing, how much time is left, and what's next.
struct NowCard: View {
    let items: [SharedStore.Item]
    let now: Date
    var onDone: (SharedStore.Item) -> Void

    @AppStorage("nowLiveActivity", store: SharedStore.defaults) private var onLockScreen = true

    var body: some View {
        let state = NowPlan.state(at: now, items: items)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: state.current == nil ? "Up next" : "Now",
                             color: state.current.map { Self.color(for: $0.category) } ?? Palette.muted)
                Spacer()
                lockScreenButton
            }
            if let current = state.current {
                currentView(current)
                if let next = state.next {
                    Rectangle().fill(Palette.line).frame(height: 1)
                    nextRow(next)
                }
            } else if let next = state.next {
                upcomingView(next)
            } else {
                Text("Nothing else on today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .card()
        .onChange(of: state.current?.id) { _, _ in
            Task { await NowActivity.sync() }
        }
    }

    private func currentView(_ item: SharedStore.Item) -> some View {
        let color = Self.color(for: item.category)
        let end = NowPlan.end(of: item)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                icon(item.symbol, color: color, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("Until " + end.formatted(date: .omitted, time: .shortened)
                         + (item.subtitle.isEmpty ? "" : " · " + item.subtitle))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(timerInterval: item.start...end, countsDown: true)
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                Text("left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button {
                    onDone(item)
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(color, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ProgressView(timerInterval: item.start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(color)
            HStack {
                Text(item.start.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(end.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.faint)
        }
    }

    private func upcomingView(_ item: SharedStore.Item) -> some View {
        let color = Self.color(for: item.category)
        return HStack(spacing: 12) {
            icon(item.symbol, color: color, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(startLabel(item))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            if Calendar.current.isDate(item.start, inSameDayAs: now) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(timerInterval: now...item.start, countsDown: true)
                        .font(.system(size: 22, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.trailing)
                    Text("free time").font(.caption2).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func nextRow(_ item: SharedStore.Item) -> some View {
        HStack(spacing: 10) {
            icon(item.symbol, color: Self.color(for: item.category), size: 30)
            Text("Then " + item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            Text(startLabel(item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
        }
    }

    private var lockScreenButton: some View {
        Button {
            onLockScreen.toggle()
            Task { await NowActivity.sync() }
        } label: {
            Label(onLockScreen ? "On Lock Screen" : "Lock Screen", systemImage: onLockScreen ? "lock.fill" : "lock.open")
                .font(.caption.weight(.bold))
                .foregroundStyle(onLockScreen ? Palette.commuteText : Palette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(onLockScreen ? Palette.commuteTint : Palette.card2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what you're doing and the time left on your Lock Screen")
    }

    private func icon(_ symbol: String, color: Color, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Palette.circle, in: Circle())
    }

    private func startLabel(_ item: SharedStore.Item) -> String {
        let time = item.start.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(item.start, inSameDayAs: now) { return "Starts " + time }
        if Calendar.current.isDateInTomorrow(item.start) { return "Tomorrow " + time }
        return item.start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    static func color(for category: String) -> Color {
        switch category {
        case "commute": return Palette.commute
        case "gym": return Palette.gym
        case "food": return Palette.food
        case "sleep": return Palette.sleep
        case "work": return Palette.work
        default: return Palette.general
        }
    }
}
