import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// "#RRGGBB" or "RRGGBB"; nil when it does not parse.
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

/// Design tokens (docs/DESIGN.md). The notch stays pure black; colour lives in small accents.
enum Theme {
    static let notch = Color.black
    static let card = Color(hex: 0x15121A)
    static let cardHi = Color(hex: 0x221C28)
    static let stroke = Color.white.opacity(0.07)
    static let text = Color(hex: 0xF7F2F6)
    static let text2 = Color(hex: 0xB8ADB7)
    static let text3 = Color(hex: 0x7C727F)
    static let blossom = Color(hex: 0xFF7EB6)
    static let berry = Color(hex: 0xE36A9A)
    static let butter = Color(hex: 0xFFD66B)
    static let lavender = Color(hex: 0xC7A6FF)
    static let mint = Color(hex: 0x7EE0B5)
    static let sky = Color(hex: 0x8CC8FF)
    static let coral = Color(hex: 0xFF7A70)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Rounded with monospaced digits, so running numbers never jitter.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let closeSpring = Animation.spring(response: 0.30, dampingFraction: 0.95)
    static let fade = Animation.easeOut(duration: 0.18)
}
