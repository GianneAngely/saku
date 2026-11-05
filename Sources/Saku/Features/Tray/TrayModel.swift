import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// One thing kept in the tray.
struct TrayItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case file, link, text }

    var id = UUID()
    var kind: Kind
    var path: String = ""          // file: absolute path
    var link: String = ""          // link: absolute URL
    var text: String = ""          // text: the snippet
    var addedAt = Date()
    /// True when the file lives in Saku's own tray folder (dropped images, copied files): removing deletes it.
    var owned = false

    var url: URL? {
        switch kind {
        case .file: URL(fileURLWithPath: path)
        case .link: URL(string: link)
        case .text: nil
        }
    }

    var name: String {
        switch kind {
        case .file: (path as NSString).lastPathComponent
        case .link: URL(string: link)?.host() ?? link
        case .text: text.split(separator: "\n").first.map(String.init) ?? text
        }
    }

    var exists: Bool { kind != .file || FileManager.default.fileExists(atPath: path) }
}

/// A folder pinned under the tray for one-click access.
struct PinnedFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var name: String { (path as NSString).lastPathComponent }
}

struct TraySave: Codable {
    var items: [TrayItem] = []
    var folders: [PinnedFolder] = []
}

@MainActor @Observable
final class TrayModel {
    private(set) var items: [TrayItem] = []
    private(set) var folders: [PinnedFolder] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let store = JSONStore<TraySave>("tray.json")
    @ObservationIgnored let ownFolder: URL

    init(prefs: Prefs) {
        self.prefs = prefs
        ownFolder = Paths.folder("Tray")
        if let s = store.load() {
            items = s.items
            folders = s.folders
        }
        items.forEach(loadThumbnail)
    }

    private func save() { store.save(TraySave(items: items, folders: folders)) }

    // MARK: Adding

    /// Adds whatever was dropped. Returns how many new items landed.
    @discardableResult
    func add(_ payload: DropPayload) -> Int {
        var added = 0
        for url in payload.files where url.isFileURL {
            var path = url.standardizedFileURL.path
            var owned = false
            if prefs.v.trayCopyFiles, let copy = copyIn(url) {
                path = copy.path
                owned = true
            }
            guard !items.contains(where: { $0.kind == .file && $0.path == path }) else { continue }
            insert(TrayItem(kind: .file, path: path, owned: owned))
            added += 1
        }
        for url in payload.links where !url.isFileURL {
            guard !items.contains(where: { $0.kind == .link && $0.link == url.absoluteString }) else { continue }
            insert(TrayItem(kind: .link, link: url.absoluteString))
            added += 1
        }
        for data in payload.images {
            guard let file = saveImage(data) else { continue }
            insert(TrayItem(kind: .file, path: file.path, owned: true))
            added += 1
        }
        for text in payload.texts {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if let u = URL(string: t), let scheme = u.scheme, ["http", "https"].contains(scheme), !t.contains(" ") {
                guard !items.contains(where: { $0.kind == .link && $0.link == t }) else { continue }
                insert(TrayItem(kind: .link, link: t))
            } else {
                guard !items.contains(where: { $0.kind == .text && $0.text == t }) else { continue }
                insert(TrayItem(kind: .text, text: t))
            }
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    private func insert(_ item: TrayItem) {
        items.insert(item, at: 0)
        loadThumbnail(item)
    }

    private func copyIn(_ url: URL) -> URL? {
        let dest = uniqueURL(name: url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func saveImage(_ data: Data) -> URL? {
        let type = UTType(filenameExtension: "png")
        let ext = NSImage(data: data) == nil ? "dat" : (data.starts(with: [0xFF, 0xD8]) ? "jpg" : type?.preferredFilenameExtension ?? "png")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dest = uniqueURL(name: "Image \(f.string(from: Date())).\(ext)")
        do {
            try data.write(to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func uniqueURL(name: String) -> URL {
        var dest = ownFolder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = ownFolder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return dest
    }

    // MARK: Removing

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        if item.owned { try? FileManager.default.removeItem(atPath: item.path) }
        save()
    }

    func clear() {
        for i in items { remove(i) }
    }

    func removeMissing() {
        for i in items where !i.exists { remove(i) }
    }

    // MARK: Actions

    func open(_ item: TrayItem) {
        switch item.kind {
        case .file, .link: if let u = item.url { NSWorkspace.shared.open(u) }
        case .text: copy(item)
        }
    }

    func reveal(_ item: TrayItem) {
        guard item.kind == .file else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func copy(_ item: TrayItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .file: pb.writeObjects([URL(fileURLWithPath: item.path) as NSURL])
        case .link: pb.setString(item.link, forType: .string)
        case .text: pb.setString(item.text, forType: .string)
        }
    }

    /// Quick Look in its own window (works while Saku stays in the background).
    func quickLook(_ item: TrayItem) {
        guard item.kind == .file, item.exists else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", item.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// What gets dragged out of the tray.
    func provider(for item: TrayItem) -> NSItemProvider {
        switch item.kind {
        case .file: NSItemProvider(contentsOf: URL(fileURLWithPath: item.path)) ?? NSItemProvider()
        case .link: NSItemProvider(object: (URL(string: item.link) ?? URL(fileURLWithPath: "/")) as NSURL)
        case .text: NSItemProvider(object: item.text as NSString)
        }
    }

    var fileURLs: [URL] { items.filter { $0.kind == .file && $0.exists }.map { URL(fileURLWithPath: $0.path) } }

    // MARK: Folders

    func pin(folder url: URL) {
        let path = url.standardizedFileURL.path
        guard !folders.contains(where: { $0.path == path }) else { return }
        folders.append(PinnedFolder(path: path))
        save()
    }

    func unpin(_ f: PinnedFolder) {
        folders.removeAll { $0.id == f.id }
        save()
    }

    func openFolder(_ f: PinnedFolder) { NSWorkspace.shared.open(URL(fileURLWithPath: f.path)) }

    // MARK: Thumbnails

    private func loadThumbnail(_ item: TrayItem) {
        guard item.kind == .file, item.exists else { return }
        let url = URL(fileURLWithPath: item.path)
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.path)
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 112, height: 112), scale: 2, representationTypes: .thumbnail)
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.nsImage else { return }
            nonisolated(unsafe) let i = img
            DispatchQueue.main.async { MainActor.assumeIsolated { self.thumbnails[id] = i } }
        }
    }
}
