import SwiftUI

/// Placeholder until gym tracking is built (templates, sets, last-time weights).
struct GymView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(eyebrow: "Coming next", title: "Gym")
                HStack(spacing: 8) {
                    ForEach(["Back", "Chest", "Legs", "Cardio"], id: \.self) { name in
                        Text(name)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Palette.card, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout templates and set logging")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text("Save your usual exercises per day, log sets in a few taps, and see last session's weights. Gym days already show on your Today timeline.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                .card()
            }
            .padding(16)
        }
        .background(Palette.bg.ignoresSafeArea())
    }
}
