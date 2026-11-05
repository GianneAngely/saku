import Foundation

@MainActor
enum CalculatorChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        func calc(_ s: String) -> String { Calculator.evaluate(s).text }
        check(calc("2 + 3 * 4") == "14" && calc("(2 + 3) * 4") == "20", "precedence and brackets")
        check(calc("2^3^2") == "512" && calc("-2^2") == "-4", "powers")
        check(calc("10 / 4") == "2.5" && calc("7 mod 3") == "1", "division and mod")
        check(calc("12% of 80") == "9.6" && calc("80 + 10%") == "88" && calc("200 - 25%") == "150", "percentages")
        check(calc("50%") == "0.5", "a bare percent")
        check(calc("sqrt(16) + 2pi") == Calculator.format(4 + 2 * Double.pi), "functions and implicit multiplication")
        check(calc("sin 30") == "0.5" && calc("5!") == "120", "degrees and factorial")
        check(calc("1,250.5 * 2") == "2501" && calc("2,5 * 2") == "5", "thousands and decimal commas")
        check(calc("3 × 4 − 2") == "10", "typographic operators")
        check(Calculator.evaluate("2 +") == .failure && Calculator.evaluate("hello") == .failure && Calculator.evaluate("1/0") == .failure, "bad input fails quietly")
        check(Calculator.evaluate("((((") == .failure && Calculator.evaluate(")") == .failure, "no crash on brackets")

        check(calc("5 km to mi") == "3.106856 mi", "kilometres to miles")
        check(calc("30 c to f") == "86 f" && calc("212 F in C") == "100 c", "temperatures")
        check(calc("3h 20m in min") == "200 min" || calc("3h 20min in min") == "200 min", "compound time")
        check(calc("2 days to h") == "48 h" && calc("90 min to h") == "1.5 h", "days and minutes")
        check(calc("2 GB to MB") == "2000 mb" && calc("1 gib to mib") == "1024 mib", "data sizes")
        check(calc("180 cm to ft") == "5.905512 ft", "centimetres to feet")
        check(Calculator.evaluate("5 kg to km") == .failure, "mismatched units fail")
        check(Calculator.evaluate("5 apples to mi") == .failure, "unknown units fail")

        let m = app.tools!
        m.clearHistory()
        m.input = "6 * 7"
        check(m.commit() == "42" && m.history.first?.result == "42", "enter keeps history")
        m.input = "oops +"
        check(m.commit() == nil && m.history.count == 1, "failed lines are not kept")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-tools", settle: 0.5) { app in
            let m = app.tools!
            m.clearHistory()
            for s in ["5 km to mi", "12% of 80", "2560 * 1440", "30 c to f"] { m.input = s; _ = m.commit() }
            m.input = "3h 20min in min"
            app.notch.mode = .open
            app.notch.tab = .tools
        },
    ]
}
