import AppKit
import Observation
import SwiftUI

/// Pick any pixel on screen (NSColorSampler, no permission needed), keep recent colours, copy them in several formats.
@MainActor @Observable
final class ColorPickerModel {
    private(set) var recent: [String] = []          // "#RRGGBB"
    @ObservationIgnored private let store = JSONStore<[String]>("colors.json")
    @ObservationIgnored private var sampler: NSColorSampler?

    init() { recent = store.load() ?? [] }

    func add(_ hex: String) {
        recent.removeAll { $0 == hex }
        recent.insert(hex, at: 0)
        recent = Array(recent.prefix(18))
        store.save(recent)
    }

    func remove(_ hex: String) {
        recent.removeAll { $0 == hex }
        store.save(recent)
    }

    /// Closes the notch so it is not in the way, then shows the system loupe.
    func pick(close: @escaping @MainActor () -> Void, done: @escaping @MainActor (String) -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                let s = NSColorSampler()
                self.sampler = s
                s.show { color in
                    guard let c = color?.usingColorSpace(.sRGB) else { return }
                    let hex = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                                     Int((c.blueComponent * 255).rounded()))
                    MainActor.assumeIsolated {
                        self.add(hex)
                        done(hex)
                    }
                }
            }
        }
    }

    enum Format: String, CaseIterable { case hex, rgb, hsl, swiftui }

    static func rgb(_ hex: String) -> (Int, Int, Int)? {
        let s = hex.replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
    }

    static func text(_ hex: String, _ f: Format) -> String {
        guard let (r, g, b) = rgb(hex) else { return hex }
        switch f {
        case .hex: return hex
        case .rgb: return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
            let mx = max(rf, gf, bf), mn = min(rf, gf, bf), l = (mx + mn) / 2
            var h = 0.0, s = 0.0
            if mx != mn {
                let d = mx - mn
                s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
                switch mx {
                case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
                case gf: h = (bf - rf) / d + 2
                default: h = (rf - gf) / d + 4
                }
                h *= 60
            }
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftui:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", Double(r) / 255, Double(g) / 255, Double(b) / 255)
        }
    }
}

struct ColorCard: View {
    let app: AppModel

    var body: some View {
        let m = app.colors!
        let format = ColorPickerModel.Format(rawValue: app.prefs.v.colorFormat) ?? .hex
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caption(text: tr("Colour picker"))
                    Spacer()
                    Menu {
                        ForEach(ColorPickerModel.Format.allCases, id: \.self) { f in
                            Button(ColorPickerModel.text("#FF7EB6", f)) { app.prefs.v.colorFormat = f.rawValue }
                        }
                    } label: {
                        Text(format.rawValue.uppercased()).font(Theme.font(10, .bold)).foregroundStyle(Theme.text2)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                Button {
                    m.pick(close: { app.commands.closeNotch() }) { hex in
                        let t = ColorPickerModel.text(hex, format)
                        app.clipboard?.copy(text: t)
                        app.flash("eyedropper.halffull", tr("Copied %@", t), tint: Color(hexString: hex) ?? Theme.blossom, seconds: 2.4)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eyedropper.halffull").font(.system(size: 12, weight: .bold))
                        Text(tr("Pick from screen")).font(Theme.font(12, .bold))
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .background(Capsule().fill(LinearGradient(colors: [Theme.blossom, Theme.lavender, Theme.sky], startPoint: .leading, endPoint: .trailing)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                if m.recent.isEmpty {
                    Text(tr("Picked colours land here. Click one to copy it.")).font(Theme.font(10.5)).foregroundStyle(Theme.text3)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 7), count: 6), spacing: 7) {
                        ForEach(m.recent, id: \.self) { hex in
                            Button {
                                let t = ColorPickerModel.text(hex, format)
                                app.clipboard?.copy(text: t)
                                app.flash("checkmark.circle.fill", tr("Copied %@", t), tint: Color(hexString: hex) ?? Theme.blossom)
                            } label: {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hexString: hex) ?? .clear)
                                    .frame(width: 24, height: 24)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                            .help(ColorPickerModel.text(hex, format))
                            .contextMenu {
                                ForEach(ColorPickerModel.Format.allCases, id: \.self) { f in
                                    Button(tr("Copy %@", ColorPickerModel.text(hex, f))) { app.clipboard?.copy(text: ColorPickerModel.text(hex, f)) }
                                }
                                Divider()
                                Button(tr("Remove"), role: .destructive) { m.remove(hex) }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 222)
    }
}
