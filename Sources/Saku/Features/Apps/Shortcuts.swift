import AppKit
import Observation
import SwiftUI

/// Apple Shortcuts through the `shortcuts` command-line tool that ships with macOS.
@MainActor @Observable
final class ShortcutsModel {
    private(set) var names: [String] = []
    private(set) var loaded = false
    private(set) var running: Set<String> = []

    @ObservationIgnored private let prefs: Prefs
    /// QA swaps the tool for a fake.
    @ObservationIgnored var tool = "/usr/bin/shortcuts"

    init(prefs: Prefs) { self.prefs = prefs }

    nonisolated static func exec(_ tool: String, _ args: [String]) async -> (status: Int32, out: String) {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    c.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
                } catch {
                    c.resume(returning: (-1, ""))
                }
            }
        }
    }

    func reload() {
        Task { @MainActor in
            let r = await Self.exec(tool, ["list"])
            names = r.out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            loaded = true
        }
    }

    /// The ones picked in settings, or all of them when none are picked.
    var shown: [String] {
        let picked = prefs.v.shortcutsShown
        return picked.isEmpty ? names : picked.filter(names.contains)
    }

    /// Runs a shortcut; reports back when it finishes.
    func run(_ name: String, done: (@MainActor (Bool) -> Void)? = nil) {
        guard !running.contains(name) else { return }
        running.insert(name)
        Task { @MainActor in
            let r = await Self.exec(tool, ["run", name])
            running.remove(name)
            done?(r.status == 0)
        }
    }

    func setDemo(_ n: [String]) {
        names = n
        loaded = true
    }

    func openApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"), configuration: .init())
    }
}

struct ShortcutsColumn: View {
    let app: AppModel

    var body: some View {
        let m = app.shortcuts!
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caption(text: tr("Shortcuts"))
                    Spacer()
                    IconButton(symbol: "arrow.clockwise", size: 9.5, tint: Theme.text3, hit: 20, help: tr("Reload")) { m.reload() }
                }
                if m.shown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.loaded ? tr("No shortcuts yet.") : tr("Loading…")).font(Theme.font(11.5)).foregroundStyle(Theme.text2)
                        PillButton(title: tr("Open Shortcuts"), icon: "square.on.square.dashed", compact: true) { m.openApp() }
                    }
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(m.shown, id: \.self) { name in
                                Button {
                                    m.run(name) { ok in
                                        app.flash(ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                                  ok ? tr("%@ done", name) : tr("%@ failed", name), tint: ok ? Theme.mint : Theme.coral)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: m.running.contains(name) ? "hourglass" : "play.fill")
                                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.sky).frame(width: 14)
                                        Text(name).font(Theme.font(11.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 6).frame(height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 200)
        .onAppear { if !m.loaded { m.reload() } }
    }
}

struct ShortcutsSection: View {
    let app: AppModel
    var body: some View {
        let m = app.shortcuts!
        @Bindable var prefs = app.prefs
        Section {
            if m.names.isEmpty {
                Text(tr("No shortcuts found. Make one in the Shortcuts app, then reload.")).foregroundStyle(.secondary)
            }
            ForEach(m.names, id: \.self) { n in
                Toggle(n, isOn: Binding(get: { prefs.v.shortcutsShown.isEmpty || prefs.v.shortcutsShown.contains(n) }, set: { on in
                    var list = prefs.v.shortcutsShown.isEmpty ? m.names : prefs.v.shortcutsShown
                    list.removeAll { $0 == n }
                    if on { list.append(n) }
                    prefs.v.shortcutsShown = list.count == m.names.count ? [] : list
                }))
            }
            HStack {
                Button(tr("Reload")) { m.reload() }
                Button(tr("Open Shortcuts")) { m.openApp() }
            }
        } header: {
            Text(tr("Shortcuts in the notch"))
        }
        .onAppear { m.reload() }
    }
}
