import AppKit
import SwiftUI

/// Dark card used for every block inside the open notch.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var fill: Color = Theme.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Round icon button with a soft hover circle.
struct IconButton: View {
    var symbol: String
    var size: CGFloat = 13
    var tint: Color = Theme.text2
    var hit: CGFloat = 26
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : tint)
                .frame(width: hit, height: hit)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.10 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Capsule button. Primary is filled with the accent, secondary is a quiet outline.
struct PillButton: View {
    var title: String
    var icon: String? = nil
    var primary = false
    var tint: Color = Theme.blossom
    var compact = false
    var minWidth: CGFloat? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: compact ? 9.5 : 10.5, weight: .bold)) }
                Text(title).font(Theme.font(compact ? 10.5 : 11.5, .semibold)).lineLimit(1)
            }
            .foregroundStyle(primary ? Color.black.opacity(0.85) : (hovering ? Theme.text : Theme.text2))
            .padding(.horizontal, compact ? 9 : 12)
            .frame(minWidth: minWidth)
            .frame(height: compact ? 22 : 26)
            .background(Capsule().fill(primary ? tint.opacity(hovering ? 1 : 0.92) : Color.white.opacity(hovering ? 0.12 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Small grey label above a group.
struct Caption: View {
    var text: String
    var body: some View {
        Text(text).font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.text3).lineLimit(1)
    }
}

/// Thin rounded progress bar.
struct ProgressTrack: View {
    var value: Double
    var tint: Color = Theme.blossom
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: max(height, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

/// Centred icon + text for empty lists and missing permissions.
struct EmptyState<Actions: View>: View {
    var icon: String
    var title: String
    var subtitle: String = ""
    var tint: Color = Theme.blossom
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text)
            if !subtitle.isEmpty {
                Text(subtitle).font(Theme.font(11)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).lineLimit(2)
            }
            actions.padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(icon: String, title: String, subtitle: String = "", tint: Color = Theme.blossom) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// Dark rounded text field that fits the notch.
struct NotchField: View {
    var placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3) }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.text3))
                .textFieldStyle(.plain)
                .font(Theme.font(12))
                .foregroundStyle(Theme.text)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Segmented switch in notch colours.
struct Segments<T: Hashable>: View {
    var items: [(T, String)]
    @Binding var selection: T
    var tint: Color = Theme.blossom

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selection
                Button { withAnimation(Theme.fade) { selection = item.0 } } label: {
                    Text(item.1)
                        .font(Theme.font(11, .semibold))
                        .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(on ? tint : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// Vertical list that fades out at the bottom edge, so a row cut by the card edge reads as "more below".
struct FadingList<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: spacing) { content }
                .padding(.bottom, 10)
        }
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
            }
        }
    }
}

/// Wraps items into rows and centres every row, so a short last row doesn't hug the left edge.
struct CenteredFlow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var out: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !row.items.isEmpty && row.width + spacing + s.width > width {
                out.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + s.width
            row.height = max(row.height, s.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { out.append(row) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(width: proposal.width ?? .infinity, subviews)
        let height = r.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, r.count - 1))
        return CGSize(width: proposal.width ?? (r.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}

/// Files that ship in Contents/Resources (or the repo's Resources folder when run from `swift build`).
enum AppResources {
    static func url(_ name: String) -> URL? {
        if let u = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: u.path) { return u }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/\(name)")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    /// A picture of your own for the alert card and the idle mark, kept outside the app and the repo:
    /// ~/Library/Application Support/Saku/mascot.png. Without it Saku shows its logo and plain symbols.
    @MainActor static let mascot: NSImage? = {
        let u = Paths.file("mascot.png")
        return FileManager.default.fileExists(atPath: u.path) ? NSImage(contentsOf: u) : nil
    }()

    @MainActor static let appIcon: NSImage? = url("AppIcon.icns").flatMap(NSImage.init(contentsOf:))
    /// The clay sakura from the app icon, for the closed notch and alert cards.
    @MainActor static let mark: NSImage? = url("mark.png").flatMap(NSImage.init(contentsOf:))
}

/// The optional mascot picture on a pink tile, crisp at any size (pixel art stays sharp at 66 pt and up).
struct MascotTile: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFE4F0), Color(hex: 0xF4A6C8)], startPoint: .top, endPoint: .bottom))
            if let img = AppResources.mascot {
                // 66 pt = two device pixels per sprite pixel: crisp. Small marks scale down smoothly instead.
                let art = size >= 60 ? 66 : size * 0.92
                Image(nsImage: img).resizable().interpolation(size >= 60 ? .none : .high).frame(width: art, height: art)
            } else {
                BlossomMark(size: size * 0.5).frame(maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
