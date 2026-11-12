import AppKit
import SwiftUI

/// The window's colours for one appearance.
struct Theme {
    /// The strip of tabs and verbs, and the status line.
    let bar: Color
    /// Under the text.
    let page: Color
    let stroke: Color
    /// Base for glyphs and small text, used at reduced opacity.
    let ink: Color

    /// A slot that holds something wears the system's accent, the one
    /// chosen in System Settings; its number is written in white.
    static let accent = Color(nsColor: .controlAccentColor)
    static let onAccent = Color.white

    static let dark = Theme(
        bar: Color(white: 0.215),
        page: Color(white: 0.18),
        stroke: .white.opacity(0.09),
        ink: .white
    )

    static let light = Theme(
        bar: Color(white: 0.975),
        page: .white,
        stroke: .black.opacity(0.11),
        ink: .black
    )

    static func of(_ scheme: ColorScheme) -> Theme { scheme == .dark ? dark : light }
}

/// The choice in the View menu: follow macOS, or pin one.
enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"

    static var current: AppearanceSetting {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceSetting.init) ?? .system
    }

    var title: String {
        switch self {
        case .system: return "Auto, as macOS"
        case .light:  return "Day"
        case .dark:   return "Night"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// The whole app wears it — the text view's own colours follow.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
