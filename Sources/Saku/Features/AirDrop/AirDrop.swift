import AppKit
import SwiftUI

/// Sends files with AirDrop through the system share sheet (macOS shows its own device picker).
@MainActor
enum AirDrop {
    /// QA replaces this so nothing opens on screen.
    static var sender: ([URL]) -> Bool = { urls in
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return false }
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }

    static var isAvailable: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    /// Only real files can go over AirDrop; links and text are turned into nothing here.
    @discardableResult
    static func send(_ payload: DropPayload) -> Bool {
        let files = payload.files.filter(\.isFileURL) + payload.links.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        return sender(files)
    }

    @discardableResult
    static func send(_ urls: [URL]) -> Bool { send(DropPayload(files: urls)) }
}

struct AirDropPane: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Section {
            Toggle(tr("Offer AirDrop when files are dragged onto the notch"), isOn: $prefs.v.airdropZone)
        } header: {
            Text("AirDrop")
        } footer: {
            Text(tr("Drop files on the AirDrop side and macOS shows nearby iPhones, iPads and Macs. Make sure AirDrop is on in Control Centre."))
        }
    }
}
