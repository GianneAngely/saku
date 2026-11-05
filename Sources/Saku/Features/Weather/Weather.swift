import AppKit
import Observation
import SwiftUI

struct City: Codable, Equatable, Identifiable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(name)|\(latitude)|\(longitude)" }
}

struct WeatherNow: Codable, Equatable {
    var temp: Double
    var feels: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
    var fetched: Date
}

/// Weather from Open-Meteo: free, no account, no key. Only the city you pick is sent.
@MainActor @Observable
final class WeatherModel {
    private(set) var now: WeatherNow?
    private(set) var results: [City] = []
    private(set) var loading = false
    private(set) var failed = false

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let cache = JSONStore<WeatherNow>("weather.json")

    init(prefs: Prefs, live: Bool) {
        self.prefs = prefs
        now = cache.load()
        guard live else { return }
        refresh()
        let t = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var city: City? { prefs.v.weatherCity }

    func setDemo(_ w: WeatherNow) { now = w }

    func search(_ q: String) {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2 else { results = []; return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: s), .init(name: "count", value: "6"), .init(name: "format", value: "json"),
                        .init(name: "language", value: Lang.shared.isIndonesian ? "id" : "en")]
        Task { @MainActor in
            guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            results = Self.parseCities(data)
        }
    }

    nonisolated static func parseCities(_ data: Data) -> [City] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let r = o["results"] as? [[String: Any]] else { return [] }
        return r.compactMap { d in
            guard let n = d["name"] as? String, let la = d["latitude"] as? Double, let lo = d["longitude"] as? Double else { return nil }
            let region = [d["admin1"] as? String, d["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            return City(name: n, region: region, latitude: la, longitude: lo)
        }
    }

    func choose(_ c: City) {
        prefs.v.weatherCity = c
        results = []
        refresh()
    }

    func refresh() {
        guard let c = city else { return }
        var comp = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comp.queryItems = [
            .init(name: "latitude", value: String(c.latitude)), .init(name: "longitude", value: String(c.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"), .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "temperature_unit", value: prefs.v.weatherFahrenheit ? "fahrenheit" : "celsius"),
        ]
        loading = true
        Task { @MainActor in
            defer { loading = false }
            guard let url = comp.url, let (data, _) = try? await URLSession.shared.data(from: url), let w = Self.parseForecast(data) else {
                failed = true
                return
            }
            failed = false
            now = w
            cache.save(w)
        }
    }

    nonisolated static func parseForecast(_ data: Data, at date: Date = Date()) -> WeatherNow? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = o["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double, let code = cur["weather_code"] as? Int else { return nil }
        let daily = o["daily"] as? [String: Any]
        let hi = (daily?["temperature_2m_max"] as? [Double])?.first ?? t
        let lo = (daily?["temperature_2m_min"] as? [Double])?.first ?? t
        return WeatherNow(temp: t, feels: cur["apparent_temperature"] as? Double ?? t, code: code, isDay: (cur["is_day"] as? Int ?? 1) == 1,
                          high: hi, low: lo, fetched: date)
    }

    /// WMO weather code to a symbol and words.
    static func describe(_ code: Int, day: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: return (day ? "sun.max.fill" : "moon.stars.fill", tr("Clear"))
        case 1, 2: return (day ? "cloud.sun.fill" : "cloud.moon.fill", tr("Partly cloudy"))
        case 3: return ("cloud.fill", tr("Cloudy"))
        case 45, 48: return ("cloud.fog.fill", tr("Foggy"))
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", tr("Drizzle"))
        case 61, 63, 66: return ("cloud.rain.fill", tr("Rain"))
        case 65, 67, 80, 81, 82: return ("cloud.heavyrain.fill", tr("Heavy rain"))
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", tr("Snow"))
        case 95, 96, 99: return ("cloud.bolt.rain.fill", tr("Thunderstorm"))
        default: return ("cloud.fill", tr("Cloudy"))
        }
    }
}

/// One line for Home: symbol, temperature, words.
struct WeatherGlance: View {
    let app: AppModel

    var body: some View {
        let m = app.weather!
        if let w = m.now, app.prefs.v.weatherCity != nil {
            let d = WeatherModel.describe(w.code, day: w.isDay)
            HStack(spacing: 5) {
                Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 12))
                Text("\(Int(w.temp.rounded()))°").font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                Text(d.text).font(Theme.font(10.5, .medium)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            .help("\(app.prefs.v.weatherCity?.name ?? "") · \(tr("High %d°, low %d°", Int(w.high.rounded()), Int(w.low.rounded())))")
        } else {
            Button { app.commands.openSettings("tools") } label: {
                Label(tr("Set your city"), systemImage: "cloud.sun.fill").font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
        }
    }
}

struct WeatherSection: View {
    let app: AppModel
    @State private var query = ""

    var body: some View {
        let m = app.weather!
        @Bindable var prefs = app.prefs
        Section {
            HStack {
                TextField(tr("Search a city"), text: $query).onSubmit { m.search(query) }
                Button(tr("Search")) { m.search(query) }
            }
            ForEach(m.results) { c in
                Button { m.choose(c); query = "" } label: {
                    HStack { Text(c.name); Text(c.region).foregroundStyle(.secondary); Spacer() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let c = prefs.v.weatherCity {
                LabeledContent(tr("City"), value: "\(c.name), \(c.region)")
            }
            Toggle(tr("Show weather on Home"), isOn: $prefs.v.weatherOnHome)
            Toggle(tr("Fahrenheit"), isOn: $prefs.v.weatherFahrenheit)
                .onChange(of: prefs.v.weatherFahrenheit) { _, _ in m.refresh() }
        } header: {
            Text(tr("Weather"))
        } footer: {
            Text(tr("From Open-Meteo, free and without an account. Only the city you choose is sent."))
        }
    }
}

struct ToolsPane: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            WeatherSection(app: app)
            Section(tr("Colour picker")) {
                Picker(tr("Copy colours as"), selection: $prefs.v.colorFormat) {
                    ForEach(ColorPickerModel.Format.allCases, id: \.self) { Text(ColorPickerModel.text("#FF7EB6", $0)).tag($0.rawValue) }
                }
            }
            ToolsPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
    }
}

/// Sections added by later branches (eye breaks, focus hooks).
@MainActor
enum ToolsPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EyeBreakSection(app: app)
    }
}
