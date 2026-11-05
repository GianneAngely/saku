import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardPane: View {
    let app: AppModel
    @State private var trusted = Paster.trusted

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Toggle(tr("Keep a clipboard history"), isOn: $prefs.v.clipboardEnabled)
                Picker(tr("Remember up to"), selection: $prefs.v.clipboardLimit) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { Text(tr("%d items", $0)).tag($0) }
                }
                Toggle(tr("Show a preview next to the list"), isOn: $prefs.v.clipboardPreview)
                Toggle(tr("Clear history when Saku quits"), isOn: $prefs.v.clipboardClearOnQuit)
            } footer: {
                Text(tr("Passwords copied from password managers are never recorded. Pinned items stay until you remove them."))
            }
            Section {
                Toggle(tr("Paste into the front app when you pick an item"), isOn: Binding(get: { prefs.v.clipboardPasteDirect }, set: { on in
                    prefs.v.clipboardPasteDirect = on
                    if on && !Paster.trusted { Paster.askForPermission() }
                    trusted = Paster.trusted
                }))
                if prefs.v.clipboardPasteDirect {
                    HStack {
                        Label(trusted ? tr("Accessibility allowed") : tr("Waiting for Accessibility permission"),
                              systemImage: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(trusted ? .green : .orange)
                        Spacer()
                        if !trusted { Button(tr("Open Accessibility settings")) { Privacy.open("Privacy_Accessibility") } }
                    }
                }
            } footer: {
                Text(tr("Pasting for you sends ⌘V to the app you were using, which macOS only allows with Accessibility permission. Off: Saku copies and you press ⌘V."))
            }
            Section(tr("Never record from these apps")) {
                ForEach(prefs.v.clipboardIgnoreApps, id: \.self) { id in
                    HStack {
                        AppIconSmall(bundleID: id)
                        Text(AppName.of(bundleID: id))
                        Spacer()
                        Button(tr("Remove")) { prefs.v.clipboardIgnoreApps.removeAll { $0 == id } }
                    }
                }
                Button(tr("Add app…")) { addIgnoredApp() }
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = Paster.trusted }
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let u = panel.url, let id = Bundle(url: u)?.bundleIdentifier else { return }
        if !app.prefs.v.clipboardIgnoreApps.contains(id) { app.prefs.v.clipboardIgnoreApps.append(id) }
    }
}

struct AppIconSmall: View {
    let bundleID: String
    var body: some View {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed").frame(width: 18, height: 18)
        }
    }
}

enum AppName {
    static func of(bundleID: String) -> String {
        guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
    }
}
