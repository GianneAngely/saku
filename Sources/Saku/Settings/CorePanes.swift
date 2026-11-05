import AppKit
import SwiftUI

struct GeneralPane: View {
    let app: AppModel
    @State private var loginOn = LoginItem.enabled
    @State private var confirmReset = false

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Toggle(tr("Open Saku at login"), isOn: Binding(get: { loginOn }, set: { on in
                    LoginItem.set(on)
                    loginOn = LoginItem.enabled
                }))
                if LoginItem.needsApproval {
                    Text(tr("Allow Saku in System Settings > General > Login Items.")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(tr("Show icon in the Dock"), isOn: $prefs.v.showInDock)
                Toggle(tr("Show icon in the menu bar"), isOn: $prefs.v.showMenuBarIcon)
                Picker(tr("Language"), selection: $prefs.v.language) {
                    Text(tr("Same as macOS")).tag("system")
                    Text("English").tag("en")
                    Text("Bahasa Indonesia").tag("id")
                }
            }
            Section(tr("Behaviour")) {
                Toggle(tr("Remember the last tab"), isOn: $prefs.v.rememberLastTab)
                Toggle(tr("Haptic feedback when the notch opens"), isOn: $prefs.v.hapticFeedback)
                Toggle(tr("Hide in full-screen apps"), isOn: $prefs.v.hideInFullscreen)
                Toggle(tr("Hide while the screen is mirrored"), isOn: $prefs.v.hideWhileMirroring)
                Picker(tr("Screens without a notch"), selection: $prefs.v.notchlessScreens) {
                    Text(tr("Invisible until hover")).tag("transparent")
                    Text(tr("Show a black notch")).tag("visible")
                    Text(tr("Hide Saku")).tag("hidden")
                }
            }
            Section {
                Toggle(tr("Hide Saku from screen sharing and screenshots"), isOn: $prefs.v.hideFromScreenSharing)
            } footer: {
                Text(tr("People in a call never see your clipboard, notes or script. The teleprompter is always hidden."))
            }
            Section {
                HStack {
                    Button(tr("Show welcome tour")) { app.commands.openSettings("welcome") }
                    Spacer()
                    Button(tr("Restore defaults…")) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(tr("Restore every setting to its default?"), isPresented: $confirmReset) {
            Button(tr("Restore defaults"), role: .destructive) { app.prefs.restoreDefaults() }
        } message: {
            Text(tr("Your notes, clipboard, tray and scripts stay as they are."))
        }
        .onAppear { loginOn = LoginItem.enabled }
    }
}

struct AppearancePane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section(tr("Open notch")) {
                SliderRow(title: tr("Width"), value: $prefs.v.openWidth, range: 560...820, step: 10) { "\(Int($0)) pt" }
                SliderRow(title: tr("Height"), value: $prefs.v.openHeight, range: 200...320, step: 4) { "\(Int($0)) pt" }
                SliderRow(title: tr("Corner radius"), value: $prefs.v.cornerRadius, range: 12...36) { "\(Int($0)) pt" }
                Toggle(tr("Liquid glass panel"), isOn: $prefs.v.glassPanel)
            }
            Section(tr("Closed notch")) {
                Picker(tr("Style"), selection: $prefs.v.closedStyle) {
                    Text(tr("Auto (most useful first)")).tag("auto")
                    Text(tr("Date and time")).tag("date")
                    Text(tr("Music bars")).tag("waveform")
                    Text(tr("Pomodoro")).tag("pomodoro")
                    Text(tr("Countdown")).tag("countdown")
                    Text(tr("Stopwatch")).tag("stopwatch")
                    Text(tr("Plain notch")).tag("none")
                }
                Picker(tr("Idle mark"), selection: $prefs.v.idleMark) {
                    Text(tr("None")).tag("none")
                    Text(tr("Blossom")).tag("blossom")
                    Text("Mascot").tag("mascot")
                }
                ColorPicker(tr("Date colour"), selection: colorBinding(\.dateColor), supportsOpacity: false)
                ColorPicker(tr("Time colour"), selection: colorBinding(\.timeColor), supportsOpacity: false)
                Toggle(tr("24-hour time"), isOn: $prefs.v.use24Hour)
            }
            Section(tr("Timing")) {
                SliderRow(title: tr("Hover before opening"), value: $prefs.v.hoverDelay, range: 0...1, step: 0.02) { String(format: "%.2f s", $0) }
                SliderRow(title: tr("Wait before closing"), value: $prefs.v.closeDelay, range: 0.05...1.5, step: 0.05) { String(format: "%.2f s", $0) }
            }
            Section {
                SliderRow(title: tr("Notch width"), value: $prefs.v.notchWidthOffset, range: -40...40) { String(format: "%+.0f pt", $0) }
                SliderRow(title: tr("Notch height"), value: $prefs.v.notchHeightOffset, range: -10...10) { String(format: "%+.0f pt", $0) }
                HStack {
                    let g = app.notch.geo
                    Text(tr("Detected: %@", g.real ? "\(Int(g.notchW - prefs.v.notchWidthOffset)) x \(Int(g.notchH - prefs.v.notchHeightOffset)) pt" : tr("no notch on this screen")))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Reset")) {
                        prefs.v.notchWidthOffset = 0
                        prefs.v.notchHeightOffset = 0
                    }
                }
            } header: {
                Text(tr("Notch fine-tuning"))
            } footer: {
                Text(tr("Only needed when the black shape does not line up with your camera housing."))
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ key: WritableKeyPath<PrefsData, String>) -> Binding<Color> {
        Binding(get: { Color(hexString: app.prefs.v[keyPath: key]) ?? .white },
                set: { app.prefs.v[keyPath: key] = $0.hexString })
    }
}

struct TabsPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        let tabs = orderedTabs
        Form {
            Section {
                List {
                    ForEach(tabs) { t in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            PaneIcon(pane: SettingsPane(rawValue: t.rawValue) ?? .general)
                            Text(t.title)
                            Spacer()
                            Toggle("", isOn: Binding(get: { !prefs.v.hiddenTabs.contains(t.rawValue) }, set: { on in
                                prefs.v.hiddenTabs.removeAll { $0 == t.rawValue }
                                if !on { prefs.v.hiddenTabs.append(t.rawValue) }
                            }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(t == .home)
                        }
                    }
                    .onMove { from, to in
                        var list = tabs.map(\.rawValue)
                        list.move(fromOffsets: from, toOffset: to)
                        prefs.v.tabOrder = list + prefs.v.tabOrder.filter { !list.contains($0) }
                    }
                }
                .frame(minHeight: CGFloat(tabs.count) * 32)
            } header: {
                Text(tr("Tabs in the notch"))
            } footer: {
                Text(tr("Drag to reorder. The first half sits left of the camera, the rest on the right. Tabs that don't fit, and every feature inside them, are in All features: the grid button in the notch."))
            }
        }
        .formStyle(.grouped)
    }

    private var orderedTabs: [Tab] {
        let order = app.prefs.v.tabOrder.compactMap(Tab.init(rawValue:))
        return (order + Tab.allCases.filter { !order.contains($0) }).filter { Tab.available.contains($0) }
    }
}

struct AboutPane: View {
    let app: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppIconView(size: 112)
            Text("Saku").font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(tr("A pocket at the top of your Mac.")).foregroundStyle(.secondary)
            Text(tr("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
                .font(.caption).foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button(tr("Show data folder")) { NSWorkspace.shared.open(Paths.dataDir) }
                Button(tr("Feature list")) {
                    if let u = AppResources.url("FEATURES.md") { NSWorkspace.shared.open(u) }
                }
            }
            Spacer()
            Text(tr("Made by Gianne Angely. No accounts, no tracking, everything stays on this Mac."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The app icon (from the bundle, or drawn live when running from `swift build`).
struct AppIconView: View {
    var size: CGFloat

    var body: some View {
        if let img = NSImage(named: "AppIcon") ?? AppResources.url("AppIcon.icns").flatMap(NSImage.init(contentsOf:)) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color(hex: 0x1A1420))
                BlossomMark(size: size * 0.5)
            }
            .frame(width: size, height: size)
        }
    }
}
