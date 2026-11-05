import AppKit
import SwiftUI

/// First-run tour, also reachable from General > Show welcome tour.
struct WelcomePane: View {
    let app: AppModel
    @State private var login = true

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    if AppResources.mascot != nil {
                        MascotTile(size: 82)
                    } else if let icon = AppResources.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 82, height: 82)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Hi, this is Saku")).font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text(tr("A pocket at the top of your Mac. Everything lives in the notch, right under the camera."))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    TourCard(icon: "cursorarrow.motionlines", tint: Theme.blossom, title: tr("Hover to open"),
                             text: tr("Move the pointer onto the notch. Move away and it tucks back in."))
                    TourCard(icon: "tray.and.arrow.down.fill", tint: Theme.sky, title: tr("Drop files on it"),
                             text: tr("Drag files to the notch to keep them in the Tray or send them with AirDrop."))
                    TourCard(icon: "music.note", tint: Theme.mint, title: tr("Live beside the camera"),
                             text: tr("Music, timers, charging and your next meeting show up next to the notch."))
                    TourCard(icon: "keyboard.fill", tint: Theme.butter, title: tr("Shortcuts"),
                             text: tr("⌃⌥Space opens Saku, ⌃⌥V the clipboard, ⌃⌥P the teleprompter. Change them in Keyboard."))
                    TourCard(icon: "text.line.first.and.arrowtriangle.forward", tint: Theme.lavender, title: tr("Teleprompter"),
                             text: tr("Your script scrolls under the camera, hidden from screen sharing."))
                    TourCard(icon: "square.grid.3x3.fill", tint: Theme.blossom, title: tr("Find anything"),
                             text: tr("The grid button in the notch (or ⌃⌥/) lists every feature and where it lives: battery health, water, timers…"))
                    TourCard(icon: "calendar.badge.plus", tint: Theme.sky, title: tr("Your Google Calendar"),
                             text: tr("Add your Google account in Settings › Calendar. Saku shows its events and can add new ones."))
                    TourCard(icon: "lock.shield.fill", tint: Theme.coral, title: tr("Private by default"),
                             text: tr("No account. Saku asks for a permission only when you first use the feature that needs it."))
                }
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.tinfine.NotchBox").first != nil {
                    Label(tr("NotchBox is running too. Quit it from its own menu so the two notches don't overlap."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Toggle(tr("Open Saku at login"), isOn: $login).toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        if login && !LoginItem.enabled { LoginItem.set(true) }
                        app.prefs.v.onboarded = true
                        NSApp.keyWindow?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            MainActor.assumeIsolated {
                                app.commands.openNotch(.home)
                                app.flash("sparkles", tr("Hover here any time"), tint: Theme.blossom, seconds: 4)
                            }
                        }
                    } label: {
                        Text(tr("Get started")).font(.system(size: 14, weight: .bold, design: .rounded)).padding(.horizontal, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.berry)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .onAppear { login = true }
    }
}

struct TourCard: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
