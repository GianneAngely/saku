import Foundation

/// A small, safe calculator: arithmetic, percentages, functions and unit conversions. No NSExpression (it can crash on bad input).
enum Calculator {
    enum Result: Equatable {
        case number(Double)
        case converted(Double, String)      // value + unit symbol
        case failure

        var text: String {
            switch self {
            case .number(let v): return Calculator.format(v)
            case .converted(let v, let unit): return Calculator.format(v) + " " + unit
            case .failure: return ""
            }
        }
    }

    static func evaluate(_ input: String) -> Result {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .failure }
        if let c = Units.convert(s) { return c }
        var p = Parser(normalize(s))
        guard let v = p.parse(), v.isFinite else { return .failure }
        return .number(v)
    }

    /// "1,250.5" thousands commas go away; a lone decimal comma ("2,5") becomes a point.
    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
        if t.range(of: #"\d{1,3}(,\d{3})+(\.\d+)?"#, options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: #"(?<=\d),(?=\d{3})"#, with: "", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"(?<=\d),(?=\d)"#, with: ".", options: .regularExpression)
        return t
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(format: "%.0f", v) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = abs(v) < 1 ? 8 : 6
        f.usesGroupingSeparator = false
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Recursive descent over tokens. `a ± b%` means a ± a·b/100; `b% of a` means a·b/100.
    struct Parser {
        enum Token: Equatable { case num(Double), id(String), op(Character), lp, rp }
        var tokens: [Token] = []
        var i = 0

        init(_ s: String) {
            let chars = Array(s.lowercased())
            var k = 0
            while k < chars.count {
                let c = chars[k]
                if c.isWhitespace { k += 1; continue }
                if c.isNumber || c == "." {
                    var j = k
                    while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
                    if j < chars.count && chars[j] == "e" && j + 1 < chars.count && (chars[j + 1].isNumber || "+-".contains(chars[j + 1])) {
                        j += 2
                        while j < chars.count && chars[j].isNumber { j += 1 }
                    }
                    tokens.append(Double(String(chars[k..<j])).map(Token.num) ?? .id("?"))
                    k = j
                } else if c.isLetter {
                    var j = k
                    while j < chars.count && (chars[j].isLetter || chars[j].isNumber) { j += 1 }
                    tokens.append(.id(String(chars[k..<j])))
                    k = j
                } else if c == "(" { tokens.append(.lp); k += 1 }
                else if c == ")" { tokens.append(.rp); k += 1 }
                else if "+-*/^%!".contains(c) { tokens.append(.op(c)); k += 1 }
                else { tokens.append(.id("?")); k += 1 }
            }
        }

        var peek: Token? { i < tokens.count ? tokens[i] : nil }

        mutating func parse() -> Double? {
            guard let v = expr(), i == tokens.count else { return nil }
            return v.value
        }

        struct Val { var value: Double; var percent = false }

        mutating func expr() -> Val? {
            guard var left = term() else { return nil }
            while case .op(let o)? = peek, o == "+" || o == "-" {
                i += 1
                guard let right = term() else { return nil }
                let r = right.percent ? left.value * right.value : right.value
                left = Val(value: o == "+" ? left.value + r : left.value - r)
            }
            return left.percent ? Val(value: left.value) : left
        }

        mutating func term() -> Val? {
            guard var left = unary() else { return nil }
            while true {
                if case .op(let o)? = peek, o == "*" || o == "/" {
                    i += 1
                    guard let r = unary() else { return nil }
                    left = Val(value: o == "*" ? left.value * r.value : left.value / r.value)
                } else if case .id("mod")? = peek {
                    i += 1
                    guard let r = unary() else { return nil }
                    left = Val(value: left.value.truncatingRemainder(dividingBy: r.value))
                } else if case .id("of")? = peek, left.percent {
                    i += 1
                    guard let r = unary() else { return nil }
                    left = Val(value: left.value * r.value)
                } else if let t = peek, startsValue(t) {          // implicit: 2pi, 3(4), 2 sqrt(9)
                    guard let r = power() else { return nil }
                    left = Val(value: left.value * r.value)
                } else {
                    return left
                }
            }
        }

        func startsValue(_ t: Token) -> Bool {
            switch t {
            case .num, .lp: return true
            case .id(let s): return s != "mod" && s != "of"
            default: return false
            }
        }

        /// Sign binds looser than powers: -2^2 = -4, and 2^-1 = 0.5.
        mutating func unary() -> Val? {
            if case .op(let o)? = peek, o == "-" || o == "+" {
                i += 1
                guard let v = unary() else { return nil }
                return Val(value: o == "-" ? -v.value : v.value, percent: v.percent)
            }
            return power()
        }

        mutating func power() -> Val? {
            guard let base = postfix() else { return nil }
            if case .op("^")? = peek {
                i += 1
                guard let e = unary() else { return nil }
                return Val(value: pow(base.value, e.value))
            }
            return base
        }

        mutating func postfix() -> Val? {
            guard var v = primary() else { return nil }
            while case .op(let o)? = peek, o == "%" || o == "!" {
                i += 1
                if o == "%" { v = Val(value: v.value / 100, percent: true) }
                else {
                    guard v.value >= 0, v.value <= 170, v.value == v.value.rounded() else { return nil }
                    v = Val(value: (1...max(1, Int(v.value))).reduce(1.0) { $0 * Double($1) })
                }
            }
            return v
        }

        mutating func primary() -> Val? {
            guard let t = peek else { return nil }
            switch t {
            case .num(let n):
                i += 1
                return Val(value: n)
            case .lp:
                i += 1
                guard let v = expr(), peek == .rp else { return nil }
                i += 1
                return v
            case .id(let name):
                i += 1
                switch name {
                case "pi": return Val(value: .pi)
                case "e": return Val(value: M_E)
                case "tau": return Val(value: 2 * .pi)
                default: break
                }
                let fns: [String: (Double) -> Double] = [
                    "sqrt": { sqrt($0) }, "cbrt": { cbrt($0) }, "abs": { abs($0) }, "round": { $0.rounded() },
                    "floor": { floor($0) }, "ceil": { ceil($0) }, "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) },
                    "sin": { sin($0 * .pi / 180) }, "cos": { cos($0 * .pi / 180) }, "tan": { tan($0 * .pi / 180) },
                    "asin": { asin($0) * 180 / .pi }, "acos": { acos($0) * 180 / .pi }, "atan": { atan($0) * 180 / .pi },
                    "exp": { exp($0) },
                ]
                guard let f = fns[name] else { return nil }
                guard let arg = primaryArgument() else { return nil }
                return Val(value: f(arg))
            default:
                return nil
            }
        }

        /// `sqrt(9)` or `sqrt 9`.
        mutating func primaryArgument() -> Double? {
            if peek == .lp {
                i += 1
                guard let v = expr(), peek == .rp else { return nil }
                i += 1
                return v.value
            }
            return power()?.value
        }
    }
}

/// "5 km to mi", "30 c in f", "3h 20m in min", "2 GB to MB", "180 cm to ft".
enum Units {
    static let table: [String: Dimension] = [
        "mm": UnitLength.millimeters, "cm": UnitLength.centimeters, "m": UnitLength.meters, "km": UnitLength.kilometers,
        "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches, "ft": UnitLength.feet, "feet": UnitLength.feet,
        "foot": UnitLength.feet, "yd": UnitLength.yards, "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "nmi": UnitLength.nauticalMiles,
        "mg": UnitMass.milligrams, "g": UnitMass.grams, "kg": UnitMass.kilograms, "oz": UnitMass.ounces, "lb": UnitMass.pounds,
        "lbs": UnitMass.pounds, "st": UnitMass.stones, "t": UnitMass.metricTons, "ton": UnitMass.metricTons,
        "ml": UnitVolume.milliliters, "l": UnitVolume.liters, "liter": UnitVolume.liters, "litre": UnitVolume.liters,
        "tsp": UnitVolume.teaspoons, "tbsp": UnitVolume.tablespoons, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
        "floz": UnitVolume.fluidOunces, "pt": UnitVolume.pints, "qt": UnitVolume.quarts, "gal": UnitVolume.gallons,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "km/h": UnitSpeed.kilometersPerHour, "kmh": UnitSpeed.kilometersPerHour, "kph": UnitSpeed.kilometersPerHour,
        "mph": UnitSpeed.milesPerHour, "m/s": UnitSpeed.metersPerSecond, "knots": UnitSpeed.knots, "kn": UnitSpeed.knots,
        "ms": UnitDuration.milliseconds, "s": UnitDuration.seconds, "sec": UnitDuration.seconds, "min": UnitDuration.minutes,
        "mins": UnitDuration.minutes, "h": UnitDuration.hours, "hr": UnitDuration.hours, "hrs": UnitDuration.hours,
        "hour": UnitDuration.hours, "hours": UnitDuration.hours,
        "b": UnitInformationStorage.bytes, "byte": UnitInformationStorage.bytes, "bytes": UnitInformationStorage.bytes,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes, "gb": UnitInformationStorage.gigabytes,
        "tb": UnitInformationStorage.terabytes, "kib": UnitInformationStorage.kibibytes, "mib": UnitInformationStorage.mebibytes,
        "gib": UnitInformationStorage.gibibytes, "bit": UnitInformationStorage.bits, "bits": UnitInformationStorage.bits,
        "m2": UnitArea.squareMeters, "km2": UnitArea.squareKilometers, "ha": UnitArea.hectares, "acre": UnitArea.acres,
        "acres": UnitArea.acres, "ft2": UnitArea.squareFeet,
        "kcal": UnitEnergy.kilocalories, "kj": UnitEnergy.kilojoules, "cal": UnitEnergy.calories,
    ]

    /// Days and weeks are not in UnitDuration, so they are converted to hours first.
    static let extraDurations: [String: Double] = ["d": 24, "day": 24, "days": 24, "w": 168, "week": 168, "weeks": 168]

    static func unit(_ s: String) -> (Dimension, Double)? {
        let k = s.lowercased()
        if let u = table[k] { return (u, 1) }
        if let hours = extraDurations[k] { return (UnitDuration.hours, hours) }
        return nil
    }

    static func convert(_ input: String) -> Calculator.Result? {
        let s = Calculator.normalize(input).lowercased()
        let parts = s.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
        guard let sepIndex = parts.lastIndex(where: { ["to", "in", "=", "->", "→", "ke"].contains($0) }),
              sepIndex > 0, sepIndex == parts.count - 2, let (target, targetScale) = unit(parts.last!) else { return nil }
        // Left side: one or more "<number><unit>" pieces (3h 20m), or "<number> <unit>".
        let left = parts[..<sepIndex].joined(separator: " ")
        let pattern = try! NSRegularExpression(pattern: #"(-?\d+(?:\.\d+)?)\s*([a-z°/0-9]+)"#)
        let matches = pattern.matches(in: left, range: NSRange(left.startIndex..., in: left))
        guard !matches.isEmpty else { return nil }
        var rest = left
        var total: Measurement<Dimension>?
        for m in matches {
            guard let nr = Range(m.range(at: 1), in: left), let ur = Range(m.range(at: 2), in: left),
                  let n = Double(left[nr]), let (u, scale) = unit(String(left[ur])),
                  type(of: u) == type(of: target) else { return nil }
            let piece = Measurement(value: n * scale, unit: u).converted(to: target)
            total = total.map { Measurement(value: $0.value + piece.value, unit: target) } ?? piece
            if let r = Range(m.range, in: left) { rest = rest.replacingOccurrences(of: String(left[r]), with: "") }
        }
        // Only "<number><unit>" pieces on the left: anything else means it was not a conversion.
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty, let t = total else { return nil }
        let value = t.value / targetScale
        return .converted(value, parts.last!)
    }
}
