import AppKit
import SwiftUI

struct TrayView: View {
    let app: AppModel
    @State private var targeted = false

    var body: some View {
        let tray = app.tray!
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Caption(text: tray.items.isEmpty ? tr("Drop files, links, text or images") : tr("%d in the tray", tray.items.count))
                Spacer()
                TrayToolbarExtras.view(app: app)
                if !tray.items.isEmpty {
                    PillButton(title: tr("Clear"), icon: "trash", compact: true) { tray.clear() }
                }
            }
            ZStack {
                if tray.items.isEmpty {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.blossom.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.blossom.opacity(targeted ? 0.12 : 0.03)))
                        .overlay {
                            EmptyState(icon: "tray.and.arrow.down.fill", title: tr("Your tray is empty"),
                                       subtitle: tr("Drag files onto the notch to keep them here, then drag them out when you need them."))
                        }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(tray.items) { item in TrayTile(app: app, item: item) }
                        }
                        .padding(.vertical, 2)
                    }
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.blossom.opacity(targeted ? 0.10 : 0)))
                }
            }
            .frame(maxHeight: .infinity)
            .onDrop(of: [.fileURL, .url, .plainText, .image], isTargeted: $targeted) { providers in
                DropReader.read(providers) { payload in
                    let n = tray.add(payload)
                    if n > 0 { app.flash("tray.and.arrow.down.fill", tr("Added %d to Tray", n)) }
                }
                return true
            }
            FolderRow(app: app)
        }
    }
}

/// Buttons other features add to the tray toolbar (AirDrop all).
@MainActor
enum TrayToolbarExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}

struct TrayTile: View {
    let app: AppModel
    let item: TrayItem
    @State private var hovering = false

    var body: some View {
        let tray = app.tray!
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                switch item.kind {
                case .file:
                    if let img = tray.thumbnails[item.id] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(4)
                    }
                    if !item.exists {
                        Image(systemName: "questionmark.folder.fill").font(.system(size: 20)).foregroundStyle(Theme.coral)
                    }
                case .link:
                    Image(systemName: "link").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.sky)
                case .text:
                    Text(item.text).font(Theme.font(8.5, .medium)).foregroundStyle(Theme.text2)
                        .lineLimit(5).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: 64, height: 64)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(hovering ? 0.25 : 0.07)))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button { tray.remove(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 17, height: 17).background(Circle().fill(Color(hex: 0x3A3340)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .help(tr("Remove from the tray"))
                }
            }
            Text(item.name).font(Theme.font(10, .medium)).foregroundStyle(item.exists ? Theme.text2 : Theme.coral)
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 78, height: 26, alignment: .top)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { tray.open(item) }
        .onTapGesture { if item.kind == .file { tray.quickLook(item) } else { tray.open(item) } }
        .onDrag { tray.provider(for: item) }
        .help(item.kind == .file ? tr("Click to preview, double-click to open, drag to move it anywhere") : item.name)
        .contextMenu {
            Button(tr("Open")) { tray.open(item) }
            if item.kind == .file {
                Button(tr("Quick Look")) { tray.quickLook(item) }
                Button(tr("Show in Finder")) { tray.reveal(item) }
            }
            Button(tr("Copy")) { tray.copy(item) }
            TrayMenuExtras.view(app: app, item: item)
            Divider()
            Button(tr("Remove"), role: .destructive) { tray.remove(item) }
        }
    }
}

/// Context-menu items other features add (AirDrop, text from image).
@MainActor
enum TrayMenuExtras {
    @ViewBuilder static func view(app: AppModel, item: TrayItem) -> some View {
        EmptyView()
    }
}

struct FolderRow: View {
    let app: AppModel

    var body: some View {
        let tray = app.tray!
        HStack(spacing: 6) {
            ForEach(tray.folders) { f in
                Button { tray.openFolder(f) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill").font(.system(size: 10.5)).foregroundStyle(Theme.sky)
                        Text(f.name).font(Theme.font(11, .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .contextMenu { Button(tr("Unpin"), role: .destructive) { tray.unpin(f) } }
                .help(f.path)
            }
            PillButton(title: tr("Pin folder"), icon: "plus", compact: true) { pickFolder() }
            Spacer(minLength: 0)
        }
    }

    private func pickFolder() {
        app.keepOpenReasons.insert("picker")
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Pin")
        NSApp.activate()
        if panel.runModal() == .OK {
            for u in panel.urls { app.tray.pin(folder: u) }
        }
        app.keepOpenReasons.remove("picker")
    }
}

struct TrayPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        let tray = app.tray!
        Form {
            Section {
                Toggle(tr("Copy dropped files into Saku"), isOn: $prefs.v.trayCopyFiles)
                Toggle(tr("Open the Tray tab after a drop"), isOn: $prefs.v.trayOpenAfterDrop)
            } footer: {
                Text(tr("Off: the tray keeps a link to the original file, so nothing is duplicated. On: Saku keeps its own copy, even if the original moves."))
            }
            Section(tr("Pinned folders")) {
                if tray.folders.isEmpty {
                    Text(tr("No pinned folders yet. Use Pin folder in the Tray tab.")).foregroundStyle(.secondary)
                }
                ForEach(tray.folders) { f in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(f.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(tr("Unpin")) { tray.unpin(f) }
                    }
                }
            }
            Section {
                HStack {
                    Button(tr("Remove missing files")) { tray.removeMissing() }
                    Button(tr("Show tray folder")) { NSWorkspace.shared.open(tray.ownFolder) }
                    Spacer()
                    Button(tr("Clear tray"), role: .destructive) { tray.clear() }
                }
            }
            TrayPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
    }
}

/// Settings sections other features add to this pane (AirDrop).
@MainActor
enum TrayPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}
