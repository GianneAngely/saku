import Foundation

@MainActor
enum WeatherChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let geo = #"{"results":[{"name":"Denpasar","latitude":-8.65,"longitude":115.21667,"country":"Indonesia","admin1":"Bali"}]}"#.data(using: .utf8)!
        let cities = WeatherModel.parseCities(geo)
        check(cities.count == 1 && cities[0].name == "Denpasar" && cities[0].region == "Bali, Indonesia", "city search results")
        check(WeatherModel.parseCities(Data("{}".utf8)).isEmpty, "no results")
        let fc = #"{"current":{"temperature_2m":28.3,"apparent_temperature":32.9,"weather_code":61,"is_day":1},"daily":{"temperature_2m_max":[31.2],"temperature_2m_min":[24.8]}}"#.data(using: .utf8)!
        let w = WeatherModel.parseForecast(fc)
        check(w?.temp == 28.3 && w?.high == 31.2 && w?.low == 24.8 && w?.code == 61, "forecast parsing")
        check(WeatherModel.parseForecast(Data("{}".utf8)) == nil, "bad forecast")
        check(WeatherModel.describe(0, day: true).symbol == "sun.max.fill" && WeatherModel.describe(0, day: false).symbol == "moon.stars.fill", "clear day and night")
        check(WeatherModel.describe(95, day: true).text == tr("Thunderstorm") && WeatherModel.describe(61, day: true).text == tr("Rain"), "weather words")
    }
}
