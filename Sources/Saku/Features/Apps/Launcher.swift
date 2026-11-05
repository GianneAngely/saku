import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AppEntry: Identifiable, Hashable {
    var url: URL
    var id: String { url.path }
    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
}

@MainActor @Observable
final class LauncherModel {
    private(set) var pinned: [String] = []          // app bundle paths
    private(set) var all: [AppEntry] = []
    var query = ""

    @ObservationIgnored private let store = JSONStore<[String]>("launcher.json")
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    static let starters = ["Google Chrome", "Visual Studio Code", "Godot", "Figma", "Spotify", "Discord", "WhatsApp", "Notion", "OBS", "Claude"]

    init() {
        if let p = store.load() {
            pinned = p
        } else {
            pinned = Self.starters.compactMap { name in
                ["/Applications/\(name).app", "/System/Applications/\(name).app"].first { FileManager.default.fileExists(atPath: $0) }
            }.prefix(8).map { $0 }
        }
        scan()
    }

    /// Every app in the usual folders (one level of subfolders, like Utilities).
    func scan() {
        let fm = FileManager.default
        var found: [URL] = []
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { continue }
            for u in items {
                if u.pathExtension == "app" { found.append(u) } else if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                    let sub = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                    found += sub.filter { $0.pathExtension == "app" }
                }
            }
        }
        var seen = Set<String>()
        all = found.map { AppEntry(url: $0) }.filter { seen.insert($0.name.lowercased()).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var pinnedEntries: [AppEntry] { pinned.filter { FileManager.default.fileExists(atPath: $0) }.map { AppEntry(url: URL(fileURLWithPath: $0)) } }

    /// Name matches first, then word starts, then anywhere.
    func search(_ q: String) -> [AppEntry] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return [] }
        func rank(_ e: AppEntry) -> Int? {
            let n = e.name.lowercased()
            if n.hasPrefix(s) { return 0 }
            if n.split(separator: " ").contains(where: { $0.hasPrefix(s) }) { return 1 }
            if n.contains(s) { return 2 }
            let initials = String(n.split(separator: " ").compactMap(\.first))
            return initials.hasPrefix(s) ? 3 : nil
        }
        return all.compactMap { e in rank(e).map { (e, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    func icon(_ e: AppEntry) -> NSImage {
        if let i = icons[e.id] { return i }
        let i = NSWorkspace.shared.icon(forFile: e.url.path)
        icons[e.id] = i
        return i
    }

    func launch(_ e: AppEntry) {
        NSWorkspace.shared.openApplication(at: e.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func pin(_ url: URL) {
        guard url.pathExtension == "app", !pinned.contains(url.path) else { return }
        pinned.append(url.path)
        store.save(pinned)
    }

    func unpin(_ e: AppEntry) {
        pinned.removeAll { $0 == e.id }
        store.save(pinned)
    }

    func move(_ e: AppEntry, by d: Int) {
        guard let i = pinned.firstIndex(of: e.id) else { return }
        let j = max(0, min(pinned.count - 1, i + d))
        pinned.swapAt(i, j)
        store.save(pinned)
    }
}

struct AppsView: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @State private var targeted = false

    var body: some View {
        let m = app.launcher!
        @Bindable var lm = m
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                NotchField(placeholder: tr("Search apps"), text: $lm.query, icon: "magnifyingglass") {
                    if let first = m.search(m.query).first { m.launch(first); m.query = ""; app.commands.closeNotch() }
                }
                .focused($focused)
                let results = m.query.isEmpty ? m.pinnedEntries : m.search(m.query)
                if results.isEmpty {
                    EmptyState(icon: "square.grid.2x2", title: m.query.isEmpty ? tr("Pin your favourite apps") : tr("No app found"),
                               subtitle: m.query.isEmpty ? tr("Drag apps here from Finder, or search and pin.") : "", tint: Theme.sky)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                            ForEach(results.prefix(36)) { e in AppTile(app: app, entry: e, pinned: m.pinned.contains(e.id)) }
                        }
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.sky.opacity(targeted ? 0.12 : 0)))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                DropReader.read(providers) { p in p.files.forEach(m.pin) }
                return true
            }
            AppsExtras.view(app: app)
        }
        .onAppear { if app.notch.focusSearch { focused = true; app.notch.focusSearch = false } }
    }
}

/// The Shortcuts column (shortcuts branch).
@MainActor
enum AppsExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}

struct AppTile: View {
    let app: AppModel
    let entry: AppEntry
    let pinned: Bool
    @State private var hovering = false

    var body: some View {
        let m = app.launcher!
        Button {
            m.launch(entry)
            m.query = ""
            app.commands.closeNotch()
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: m.icon(entry)).resizable().frame(width: 40, height: 40)
                    .scaleEffect(hovering ? 1.08 : 1)
                Text(entry.name).font(Theme.font(10, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            if pinned {
                Button(tr("Move left")) { m.move(entry, by: -1) }
                Button(tr("Move right")) { m.move(entry, by: 1) }
                Button(tr("Unpin")) { m.unpin(entry) }
            } else {
                Button(tr("Pin")) { m.pin(entry.url) }
            }
            Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
    }
}

struct AppsPane: View {
    let app: AppModel
    var body: some View {
        let m = app.launcher!
        Form {
            Section(tr("Pinned apps")) {
                ForEach(m.pinnedEntries) { e in
                    HStack {
                        Image(nsImage: m.icon(e)).resizable().frame(width: 20, height: 20)
                        Text(e.name)
                        Spacer()
                        Button(tr("Unpin")) { m.unpin(e) }
                    }
                }
                Button(tr("Add app…")) {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.application]
                    p.allowsMultipleSelection = true
                    p.directoryURL = URL(fileURLWithPath: "/Applications")
                    if p.runModal() == .OK { p.urls.forEach(m.pin) }
                }
            }
            AppsPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
    }
}

@MainActor
enum AppsPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}
