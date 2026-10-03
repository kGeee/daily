import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// A color that switches between two hex values for light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// Every color in the app. Matches the design mockups (light + dark).
enum Palette {
    static let bg = Color(light: 0xF3F4F6, dark: 0x0B0C0F)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1C21)
    static let card2 = Color(light: 0xF6F7F9, dark: 0x24262C)
    static let ink = Color(light: 0x15171C, dark: 0xF2F3F5)
    static let muted = Color(light: 0x5B616E, dark: 0x9AA0AB)
    static let faint = Color(light: 0x8A909C, dark: 0x6B717D)
    static let line = Color(light: 0xE3E5EA, dark: 0x2E3138)
    static let idle = Color(light: 0xD5D8DE, dark: 0x3A3D45)
    static let circle = Color(light: 0xEEF0F3, dark: 0x2A2D34)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0B0C0F)

    static let commute = Color(light: 0x2560C9, dark: 0x4C8DF0)
    static let commuteTint = Color(light: 0xE6EEFB, dark: 0x1C2A44)
    static let commuteText = Color(light: 0x1D4FA8, dark: 0x8DB7F7)

    static let gym = Color(light: 0xC2531F, dark: 0xEE7A45)
    static let gymTint = Color(light: 0xFBEDE5, dark: 0x3A2418)
    static let gymText = Color(light: 0xA1441A, dark: 0xF4A27C)

    static let food = Color(light: 0x23744A, dark: 0x3FAE74)
    static let foodTint = Color(light: 0xE3F1E9, dark: 0x17301F)
    static let foodText = Color(light: 0x1B5E3B, dark: 0x7FD3A3)

    static let sleep = Color(light: 0x4F4FC4, dark: 0x8C8CF0)
    static let sleepText = Color(light: 0x4F4FC4, dark: 0xA9A9F5)

    static let water = Color(light: 0x157A97, dark: 0x5BC0DE)
    static let waterTint = Color(light: 0xE2F2F7, dark: 0x15333D)
    static let waterText = Color(light: 0x0F5E75, dark: 0xA8E0EE)

    static let general = Color(light: 0xB83A6E, dark: 0xF07AA8)
    static let generalTint = Color(light: 0xF9E6EE, dark: 0x3A1C29)

    static let work = Color(light: 0x6B717D, dark: 0x9AA0AB)

    static let danger = Color(light: 0xD23B3B, dark: 0xFF6B6B)

    // Detail-sheet headers: a muted, deeper version of each category color, with light text on top.
    static let heroCommute = Color(light: 0x4C6FAE, dark: 0x2B4271)
    static let heroGym = Color(light: 0xAE6941, dark: 0x6A3B22)
    static let heroFood = Color(light: 0x4E8763, dark: 0x2B4F38)
    static let heroSleep = Color(light: 0x5B708C, dark: 0x34435A)
    static let heroWork = Color(light: 0x69707D, dark: 0x3C414B)
    static let heroGeneral = Color(light: 0xA45C7F, dark: 0x66344D)
    static let heroFocus = Color(light: 0xAE564C, dark: 0x6B302A)
    /// Text and icons on a hero header.
    static let heroOn = Color(light: 0xFFFFFF, dark: 0xF2F3F5)
    /// The big icon capsule and round buttons on a hero header.
    static let heroPill = Color(light: 0xF4F5F7, dark: 0x22252B)

    static let focus = Color(light: 0xC9433A, dark: 0xF26B5B)
    static let focusTint = Color(light: 0xFBE9E7, dark: 0x3A1E1B)
    static let focusText = Color(light: 0xA8362E, dark: 0xF7A097)
    static let caltrain = Color(light: 0x6B717D, dark: 0xB9BEC8)
    static let caltrainTint = Color(light: 0xEEF0F3, dark: 0x2A2D34)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = Palette.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = Palette.card) -> some View {
        modifier(CardStyle(padding: padding, fill: fill))
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = Palette.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: eyebrow)
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Palette.ink)
        }
        .padding(.top, 8)
    }
}

/// A vertical line, used for the dashed connectors on the timeline.
struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}
