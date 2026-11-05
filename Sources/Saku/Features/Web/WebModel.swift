import AppKit
import Observation
import SwiftUI
import WebKit

enum SearchEngine: String, CaseIterable, Codable {
    case google, duckduckgo, bing, perplexity, ecosia

    var title: String {
        switch self {
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        case .perplexity: "Perplexity"
        case .ecosia: "Ecosia"
        }
    }

    func url(for query: String) -> URL? {
        var c: URLComponents
        switch self {
        case .google: c = URLComponents(string: "https://www.google.com/search")!
        case .duckduckgo: c = URLComponents(string: "https://duckduckgo.com/")!
        case .bing: c = URLComponents(string: "https://www.bing.com/search")!
        case .perplexity: c = URLComponents(string: "https://www.perplexity.ai/search")!
        case .ecosia: c = URLComponents(string: "https://www.ecosia.org/search")!
        }
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url
    }
}

/// Takes typing in the notch: the panel becomes key when you click into a page.
final class NotchWebView: WKWebView {
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor @Observable
final class WebModel: NSObject, WKNavigationDelegate {
    var address = ""
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var loading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// No page yet: the start page (search and bookmarks) shows instead.
    private(set) var blank = true

    @ObservationIgnored private(set) lazy var view: NotchWebView = makeView()
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    static let mobileAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    init(prefs: Prefs) {
        self.prefs = prefs
        super.init()
    }

    private func makeView() -> NotchWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = false
        let v = NotchWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 300), configuration: config)
        v.navigationDelegate = self
        v.allowsBackForwardNavigationGestures = true
        v.setValue(false, forKey: "drawsBackground")
        applyPrefs(to: v)
        observations = [
            v.observe(\.estimatedProgress) { [weak self] w, _ in let p = w.estimatedProgress; DispatchQueue.main.async { MainActor.assumeIsolated { self?.progress = p } } },
            v.observe(\.isLoading) { [weak self] w, _ in let l = w.isLoading; DispatchQueue.main.async { MainActor.assumeIsolated { self?.loading = l } } },
            v.observe(\.title) { [weak self] w, _ in let t = w.title ?? ""; DispatchQueue.main.async { MainActor.assumeIsolated { self?.title = t } } },
            v.observe(\.url) { [weak self] w, _ in let u = w.url; DispatchQueue.main.async { MainActor.assumeIsolated { self?.urlChanged(u) } } },
            v.observe(\.canGoBack) { [weak self] w, _ in let b = w.canGoBack; DispatchQueue.main.async { MainActor.assumeIsolated { self?.canGoBack = b } } },
            v.observe(\.canGoForward) { [weak self] w, _ in let f = w.canGoForward; DispatchQueue.main.async { MainActor.assumeIsolated { self?.canGoForward = f } } },
        ]
        return v
    }

    func applyPrefs(to v: WKWebView? = nil) {
        let w = v ?? view
        w.customUserAgent = prefs.v.webMobile ? Self.mobileAgent : nil
        w.pageZoom = prefs.v.webZoom
    }

    private func urlChanged(_ u: URL?) {
        url = u
        if let u, u.absoluteString != "about:blank" {
            blank = false
            address = u.absoluteString
        }
    }

    /// A URL, a bare domain, or words to search for.
    static func target(for input: String, engine: SearchEngine) -> URL? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) { return u }
        let domainish = !s.contains(" ") && s.contains(".") && s.split(separator: ".").last.map { $0.count >= 2 && $0.allSatisfy(\.isLetter) } == true
        if domainish || s.hasPrefix("localhost") { return URL(string: (s.hasPrefix("localhost") ? "http://" : "https://") + s) }
        return engine.url(for: s)
    }

    func go(_ input: String? = nil) {
        guard let u = Self.target(for: input ?? address, engine: SearchEngine(rawValue: prefs.v.webSearchEngine) ?? .google) else { return }
        load(u)
    }

    func load(_ u: URL) {
        blank = false
        address = u.absoluteString
        view.load(URLRequest(url: u))
    }

    func back() { view.goBack() }
    func forward() { view.goForward() }
    func reload() {
        if loading { view.stopLoading() } else { view.reload() }
    }

    func home() {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        blank = true
        address = ""
        title = ""
    }

    /// Opens the page in the default browser.
    func openOutside() {
        if let u = url ?? URL(string: address), u.scheme?.hasPrefix("http") == true { NSWorkspace.shared.open(u) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Links that want a new window open in the same view.
        if action.targetFrame == nil, let u = action.request.url {
            webView.load(URLRequest(url: u))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
