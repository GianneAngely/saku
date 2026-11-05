import AppKit
import SwiftUI

/// Saku's app icon: the top of a screen with a black notch "pocket" (stitched edge), and a blossom
/// blooming out of it. Fills the full macOS squircle grid (824 pt on a 1024 canvas) so macOS 26 shows
/// it as is. `Saku --make-icon DIR` writes an .iconset; build.sh turns it into AppIcon.icns.
struct IconArt: View {
    var body: some View {
        Canvas { c, size in
            let s = size.width / 1024
            let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            let squircle = Path(roundedRect: tile, cornerRadius: 186 * s, style: .continuous)

            // Shadow under the tile.
            var sh = c
            sh.addFilter(.shadow(color: .black.opacity(0.35), radius: 18 * s, x: 0, y: 10 * s))
            sh.fill(squircle, with: .color(Color(hex: 0x120C16)))

            c.clip(to: squircle)
            c.fill(squircle, with: .linearGradient(Gradient(colors: [Color(hex: 0x3B2145), Color(hex: 0x1D1223), Color(hex: 0x0F0A13)]),
                                                   startPoint: CGPoint(x: tile.midX, y: tile.minY), endPoint: CGPoint(x: tile.midX, y: tile.maxY)))
            // Soft blossom glow.
            c.fill(Path(ellipseIn: CGRect(x: tile.midX - 330 * s, y: tile.minY + 200 * s, width: 660 * s, height: 560 * s)),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0xFF7EB6, alpha: 0.38), .clear]),
                                         center: CGPoint(x: tile.midX, y: tile.minY + 470 * s), startRadius: 0, endRadius: 330 * s))

            // The notch pocket hanging from the top edge.
            let nw = 452 * s, nh = 214 * s, nr = 92 * s
            let notch = CGRect(x: tile.midX - nw / 2, y: tile.minY - 40 * s, width: nw, height: nh + 40 * s)
            c.fill(Path(roundedRect: notch, cornerRadius: nr, style: .continuous), with: .color(.black))
            // Stitching along the pocket edge.
            let inset = notch.insetBy(dx: 26 * s, dy: 26 * s)
            var stitch = Path()
            let r = nr - 26 * s
            stitch.move(to: CGPoint(x: inset.minX, y: tile.minY - 10 * s))
            stitch.addLine(to: CGPoint(x: inset.minX, y: inset.maxY - r))
            stitch.addArc(tangent1End: CGPoint(x: inset.minX, y: inset.maxY), tangent2End: CGPoint(x: inset.minX + r, y: inset.maxY), radius: r)
            stitch.addLine(to: CGPoint(x: inset.maxX - r, y: inset.maxY))
            stitch.addArc(tangent1End: CGPoint(x: inset.maxX, y: inset.maxY), tangent2End: CGPoint(x: inset.maxX, y: inset.maxY - r), radius: r)
            stitch.addLine(to: CGPoint(x: inset.maxX, y: tile.minY - 10 * s))
            c.stroke(stitch, with: .color(Color(hex: 0xFF9CC8, alpha: 0.75)),
                     style: StrokeStyle(lineWidth: 9 * s, lineCap: .round, dash: [26 * s, 22 * s]))
            // Camera dot.
            c.fill(Path(ellipseIn: CGRect(x: tile.midX - 17 * s, y: tile.minY + 62 * s, width: 34 * s, height: 34 * s)),
                   with: .color(Color(hex: 0x1C1A2A)))
            c.fill(Path(ellipseIn: CGRect(x: tile.midX - 7 * s, y: tile.minY + 72 * s, width: 12 * s, height: 12 * s)),
                   with: .color(Color(hex: 0x3A3F6B)))

            // Blossom blooming out of the pocket.
            let center = CGPoint(x: tile.midX, y: tile.minY + 486 * s)
            for i in 0..<5 {
                var p = c
                p.translateBy(x: center.x, y: center.y)
                p.rotate(by: .degrees(Double(i) * 72))
                let petal = petalPath(w: 196 * s, tip: 246 * s, base: 14 * s)
                p.addFilter(.shadow(color: Color(hex: 0x6E1E44, alpha: 0.5), radius: 12 * s, y: 6 * s))
                p.fill(petal, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFD6E7), Color(hex: 0xFF9AC6), Color(hex: 0xEE6FA5)]),
                                                    startPoint: CGPoint(x: 0, y: -246 * s), endPoint: CGPoint(x: 0, y: -20 * s)))
                var vein = Path()
                vein.move(to: CGPoint(x: 0, y: -92 * s))
                vein.addLine(to: CGPoint(x: 0, y: -168 * s))
                p.stroke(vein, with: .color(Color.white.opacity(0.32)), style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
            }
            // Centre and stamens.
            c.fill(Path(ellipseIn: CGRect(x: center.x - 62 * s, y: center.y - 62 * s, width: 124 * s, height: 124 * s)),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xFFC94D)]), center: center, startRadius: 0, endRadius: 62 * s))
            for i in 0..<10 {
                let a = Double(i) * 36 * .pi / 180
                let pt = CGPoint(x: center.x + cos(a) * 38 * s, y: center.y + sin(a) * 38 * s)
                c.fill(Path(ellipseIn: CGRect(x: pt.x - 9 * s, y: pt.y - 9 * s, width: 18 * s, height: 18 * s)), with: .color(Color(hex: 0xF29A2E)))
            }

            // Two sparkles.
            for (pt, r) in [(CGPoint(x: tile.minX + 170 * s, y: tile.minY + 330 * s), 34 * s), (CGPoint(x: tile.maxX - 150 * s, y: tile.maxY - 170 * s), 46 * s)] {
                var sp = c
                sp.translateBy(x: pt.x, y: pt.y)
                sp.fill(sparkle(r), with: .color(Color(hex: 0xFFE08A)))
            }
        }
    }

    /// Rounded petal pointing up (negative y) from near the centre, with a small V cut at the tip like a sakura petal.
    private func petalPath(w: CGFloat, tip t: CGFloat, base b: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -b))
        p.addCurve(to: CGPoint(x: -w / 2, y: -t * 0.62), control1: CGPoint(x: -w * 0.20, y: -b - t * 0.06), control2: CGPoint(x: -w / 2, y: -t * 0.38))
        p.addCurve(to: CGPoint(x: -w * 0.12, y: -t), control1: CGPoint(x: -w / 2, y: -t * 0.88), control2: CGPoint(x: -w * 0.30, y: -t))
        p.addLine(to: CGPoint(x: 0, y: -t * 0.93))
        p.addLine(to: CGPoint(x: w * 0.12, y: -t))
        p.addCurve(to: CGPoint(x: w / 2, y: -t * 0.62), control1: CGPoint(x: w * 0.30, y: -t), control2: CGPoint(x: w / 2, y: -t * 0.88))
        p.addCurve(to: CGPoint(x: 0, y: -b), control1: CGPoint(x: w / 2, y: -t * 0.38), control2: CGPoint(x: w * 0.20, y: -b - t * 0.06))
        p.closeSubpath()
        return p
    }

    private func sparkle(_ r: CGFloat) -> Path {
        var p = Path()
        let c = r * 0.2
        p.move(to: CGPoint(x: 0, y: -r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: c, y: -c))
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: c, y: c))
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -c, y: c))
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -c, y: -c))
        return p
    }

    /// Writes AppIcon.iconset (every size macOS wants) into `dir`.
    @MainActor static func writeIconset(to dir: URL) {
        let set = dir.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let r = ImageRenderer(content: IconArt().frame(width: CGFloat(px), height: CGFloat(px)))
                r.scale = 1
                guard let cg = r.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: set.appendingPathComponent(name))
            }
        }
        print("wrote \(set.path)")
    }
}
