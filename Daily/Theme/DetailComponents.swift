import SwiftUI

// Shared pieces for the detail sheets (events, timeline blocks, meals): a colored header with a big
// icon capsule on the timeline line, then rounded cards of rows underneath.

extension BlockCategory {
    /// Header color for detail sheets.
    var hero: Color {
        switch self {
        case .commute: return Palette.heroCommute
        case .gym: return Palette.heroGym
        case .food: return Palette.heroFood
        case .sleep: return Palette.heroSleep
        case .work: return Palette.heroWork
        case .general: return Palette.heroGeneral
        }
    }
}

/// The colored top of a detail sheet.
struct DetailHero<Title: View, Trailing: View>: View {
    let background: Color
    let symbol: String
    let iconColor: Color
    let timeText: String
    /// Small icons under the title (e.g. repeat).
    var badges: [String] = []
    /// nil hides the check circle.
    var done: Bool? = nil
    var onToggle: () -> Void = {}
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var title: () -> Title

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The timeline line running into the icon capsule.
            VLine()
                .stroke(Palette.heroOn.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
                .frame(width: 3, height: 86)
                .padding(.leading, 64)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    roundButton("xmark", label: "Close", action: onClose)
                    Spacer()
                    trailing()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Capsule()
                            .fill(Palette.heroPill)
                            .overlay(Capsule().strokeBorder(Palette.heroOn.opacity(0.9), lineWidth: 3))
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    .frame(width: 70, height: 128)
                    .padding(.leading, 30)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(timeText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.heroOn.opacity(0.75))
                        title()
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Palette.heroOn)
                            .tint(Palette.heroOn)
                        Rectangle()
                            .fill(Palette.heroOn.opacity(0.45))
                            .frame(height: 1)
                        if !badges.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(badges, id: \.self) { badge in
                                    Image(systemName: badge)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Palette.heroOn.opacity(0.75))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let done {
                        Button(action: onToggle) {
                            ZStack {
                                Circle()
                                    .strokeBorder(Palette.heroOn, lineWidth: 2.5)
                                    .background(Circle().fill(done ? Palette.heroOn : Color.clear))
                                if done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(background)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.success, trigger: done)
                        .accessibilityLabel(done ? "Mark not done" : "Mark done")
                    }
                }
                .padding(.trailing, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }
}

extension DetailHero where Trailing == EmptyView {
    init(background: Color, symbol: String, iconColor: Color, timeText: String, badges: [String] = [],
         done: Bool? = nil, onToggle: @escaping () -> Void = {}, onClose: @escaping () -> Void,
         @ViewBuilder title: @escaping () -> Title) {
        self.init(background: background, symbol: symbol, iconColor: iconColor, timeText: timeText,
                  badges: badges, done: done, onToggle: onToggle, onClose: onClose,
                  trailing: { EmptyView() }, title: title)
    }
}

/// Round light button used on hero headers (close, more, save).
func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 46, height: 46)
            .background(Palette.heroPill.opacity(0.9), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
}

/// A detail sheet: hero on top, cards below, scrolling together.
struct DetailSheetLayout<Hero: View, Content: View>: View {
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero()
                VStack(spacing: 16) {
                    content()
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 600, idealHeight: 760)
        #endif
    }
}

/// A rounded card of rows separated by inset lines.
struct DetailCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A divider indented past the row icon.
struct DetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: 1)
            .padding(.leading, 44)
    }
}

/// Icon · title · value · chevron.
struct DetailRowLabel: View {
    let symbol: String
    var tint: Color = Palette.commute
    let title: String
    var value: String? = nil
    var chevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
            Text(title)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// A row that opens an inline picker underneath when tapped.
struct DetailExpandableRow<Editor: View>: View {
    let symbol: String
    var tint: Color = Palette.commute
    let title: String
    var value: String? = nil
    @Binding var expanded: Bool
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    DetailRowLabel(symbol: symbol, tint: tint, title: title, value: value, chevron: false)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            if expanded {
                editor()
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

/// Free-form notes card.
struct DetailNotesCard: View {
    @Binding var text: String
    var placeholder = "Add notes, links or phone numbers…"

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.body)
            .foregroundStyle(Palette.ink)
            .lineLimit(4...12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Big red delete button in its own card.
struct DetailDeleteButton: View {
    var title = "Delete"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: "trash")
                .font(.headline)
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Big filled button for the main action at the bottom of a sheet.
struct DetailPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var fill: Color = Palette.commute
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A sliding pill segmented control (used instead of the plain system one).
struct PillSegment<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var namespace

    init(_ options: [Value], selection: Binding<Value>, title: @escaping (Value) -> String) {
        self.options = options
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isOn ? .bold : .semibold))
                        .foregroundStyle(isOn ? Palette.ink : Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(Palette.card)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "selected", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.line.opacity(0.7), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Small rounded chip that can be selected (used for meal slot, source, etc.).
struct ChoiceChip: View {
    let title: String
    var symbol: String? = nil
    let isOn: Bool
    var tint: Color = Palette.commute
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn ? Palette.onAccent : Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? tint : Palette.card2, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}
