import AppKit
import SwiftUI
import WebKit

struct WebTab: View {
    let app: AppModel

    var body: some View {
        let w = app.web!
        @Bindable var wm = w
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", size: 11, tint: w.canGoBack ? Theme.text : Theme.text3, hit: 24, help: tr("Back")) { w.back() }
                    .disabled(!w.canGoBack)
                IconButton(symbol: "chevron.right", size: 11, tint: w.canGoForward ? Theme.text : Theme.text3, hit: 24, help: tr("Forward")) { w.forward() }
                    .disabled(!w.canGoForward)
                IconButton(symbol: w.loading ? "xmark" : "arrow.clockwise", size: 11, tint: Theme.text2, hit: 24, help: w.loading ? tr("Stop") : tr("Reload")) { w.reload() }
                ZStack(alignment: .bottomLeading) {
                    NotchField(placeholder: tr("Search %@ or type a website", (SearchEngine(rawValue: app.prefs.v.webSearchEngine) ?? .google).title),
                               text: $wm.address, icon: w.url?.scheme == "https" ? "lock.fill" : "magnifyingglass") { w.go() }
                    if w.loading {
                        Capsule().fill(Theme.sky).frame(width: max(8, 200 * w.progress), height: 2).padding(.leading, 8).padding(.bottom, 1)
                    }
                }
                WebToolbarExtras.view(app: app)
                IconButton(symbol: "house", size: 11, tint: Theme.text2, hit: 24, help: tr("Start page")) { w.home() }
                IconButton(symbol: "arrow.up.forward.app", size: 11, tint: Theme.text2, hit: 24, help: tr("Open in your browser")) { w.openOutside() }
            }
            ZStack {
                WebViewHost(view: w.view)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(w.blank ? 0 : 1)
                if w.blank {
                    WebStartPage(app: app)
                }
            }
        }
    }
}

/// Buttons added by the bookmarks branch.
@MainActor
enum WebToolbarExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}

struct WebViewHost: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WebStartPage: View {
    let app: AppModel

    var body: some View {
        Card(padding: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.sky)
                    Text(tr("Quick look-ups without leaving what you are doing")).font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.text2)
                }
                WebStartExtras.view(app: app)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The bookmarks grid on the start page (bookmarks branch).
@MainActor
enum WebStartExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}

struct WebPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker(tr("Search engine"), selection: $prefs.v.webSearchEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(tr("Use mobile layouts (fit the notch better)"), isOn: $prefs.v.webMobile)
                SliderRow(title: tr("Page zoom"), value: $prefs.v.webZoom, range: 0.6...1.2, step: 0.05) { "\(Int($0 * 100))%" }
            }
            Section(tr("Size of the Web tab")) {
                SliderRow(title: tr("Width"), value: $prefs.v.webWidth, range: 560...1000, step: 10) { "\(Int($0)) pt" }
                SliderRow(title: tr("Height"), value: $prefs.v.webHeight, range: 236...640, step: 10) { "\(Int($0)) pt" }
            }
            Section {
                Button(tr("Clear cookies and website data")) {
                    WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
                }
            }
            WebPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
        .onChange(of: prefs.v.webMobile) { _, _ in app.web.applyPrefs() }
        .onChange(of: prefs.v.webZoom) { _, _ in app.web.applyPrefs() }
    }
}

@MainActor
enum WebPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}
