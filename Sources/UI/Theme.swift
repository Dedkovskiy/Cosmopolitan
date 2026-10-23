import SwiftUI

// The look, after Aberration Ark's green frost (Frost 0.80, dark, Emerald accent, no effects): a see-through window with the desktop
// blurred behind it, a faint emerald wash from the top (Aberration Ark's warm one at the bottom left out), dark glass cards. Public AppKit only (NSVisualEffectView,
// macOS 14+); Reduce transparency in System Settings › Accessibility turns the frost solid by itself.
enum Theme {
    static let accent = Color(hex: 0x10B981)    // Emerald
    static let surface = Color(hex: 0x0E1117)   // the veil of a card
    static let frost = 0.8
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}

// The desktop blurred behind the window; the window itself turns see-through once this view is in it.
struct FrostBackground: NSViewRepresentable {
    final class Frost: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.isOpaque = false; w.backgroundColor = .clear; w.titlebarAppearsTransparent = true
        }
    }
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = Frost(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; v.appearance = NSAppearance(named: .darkAqua); return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

extension View {
    // A window's or sheet's background, dark scheme and emerald controls. The dark veil keeps text readable over a bright desktop.
    func frost() -> some View {
        background {
            ZStack {
                FrostBackground()
                Theme.surface.opacity(0.45)
                LinearGradient(colors: [Theme.accent.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
            }.ignoresSafeArea()
        }.tint(Theme.accent).preferredColorScheme(.dark)
    }

    func glassCard(_ radius: CGFloat = 18, veil: Double = Theme.frost) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Theme.surface.opacity(veil)).overlay(shape.strokeBorder(.white.opacity(0.08))).shadow(color: .black.opacity(0.22), radius: 5, y: 2))
    }

    // Liquid Glass buttons where the system has them (macOS 26), capsules before. Plain glass takes on the tint around it, so the
    // secondary one clears it, and the primary one sets its own (a clear tint around it would empty it).
    @ViewBuilder func primaryButton() -> some View {
        let v = buttonBorderShape(.capsule).tint(Theme.accent)
        if #available(macOS 26, *) { v.buttonStyle(.glassProminent) } else { v.buttonStyle(.borderedProminent) }
    }
    @ViewBuilder func secondaryButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass).tint(.clear) } else { buttonStyle(.bordered).buttonBorderShape(.capsule) }
    }
}

// A label with an emerald icon, for lists of features and checks.
struct AccentIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) { configuration.icon.foregroundStyle(Theme.accent).frame(width: 22); configuration.title }
    }
}
