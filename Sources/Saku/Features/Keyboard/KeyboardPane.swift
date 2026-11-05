import AppKit
import SwiftUI

struct KeyboardPane: View {
    let app: AppModel
    @State private var recording: HotkeyAction?
    @State private var monitor: Any?

    var body: some View {
        let h = app.hotkeys!
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { a in
                    HStack {
                        Text(a.title)
                        Spacer()
                        if h.conflicts.contains(a) {
                            Label(tr("Taken"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                                .help(tr("Another app (or another Saku action) already uses these keys. Pick different keys."))
                        }
                        Button {
                            recording == a ? stopRecording() : startRecording(a)
                        } label: {
                            Text(recording == a ? tr("Type keys…") : (h.spec(a)?.display ?? tr("None")))
                                .monospaced()
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.bordered)
                        .tint(recording == a ? .pink : nil)
                        if h.spec(a) != nil {
                            Button { h.set(a, nil) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help(tr("Remove shortcut"))
                        }
                    }
                }
            } header: {
                Text(tr("Global shortcuts"))
            } footer: {
                Text(tr("They work from any app. Click a shortcut, then press the new keys with ⌃, ⌥ or ⌘. Esc cancels, ⌫ removes it."))
            }
            Section {
                Button(tr("Restore default shortcuts")) { h.resetAll() }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ a: HotkeyAction) {
        stopRecording()
        recording = a
        app.hotkeys.unregisterAll()   // so pressing a current shortcut records it instead of running it
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let code = e.keyCode
            let bare = e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            let spec = HotkeySpec(event: e)
            MainActor.assumeIsolated {
                if code == 53 { stopRecording() }                          // Esc cancels
                else if code == 51 && bare { app.hotkeys.set(a, nil); stopRecording() }   // ⌫ removes
                else if let spec { app.hotkeys.set(a, spec); stopRecording() }
                else { NSSound.beep() }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = nil
        app.hotkeys.apply()
    }
}
