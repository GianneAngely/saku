import AppKit
import Observation
import SwiftUI

struct CalcEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var input: String
    var result: String
}

@MainActor @Observable
final class ToolsModel {
    var input = ""
    private(set) var history: [CalcEntry] = []
    @ObservationIgnored private let store = JSONStore<[CalcEntry]>("calculator.json")

    init() { history = store.load() ?? [] }

    var result: Calculator.Result { Calculator.evaluate(input) }

    /// Enter: keep the line in history and copy the answer.
    func commit() -> String? {
        let r = result
        guard r != .failure else { return nil }
        history.insert(CalcEntry(input: input, result: r.text), at: 0)
        history = Array(history.prefix(30))
        store.save(history)
        return r.text
    }

    func clearHistory() {
        history = []
        store.save(history)
    }
}

struct ToolsView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            CalculatorCard(app: app).spotlight(app, "calculator")
            ToolsExtras.view(app: app)
        }
    }
}

/// Cards added by later branches (colour picker).
@MainActor
enum ToolsExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        ColorCard(app: app).spotlight(app, "colour")
    }
}

struct CalculatorCard: View {
    let app: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        let m = app.tools!
        @Bindable var tm = m
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caption(text: tr("Calculator and converter"))
                    Spacer()
                    if !m.history.isEmpty {
                        IconButton(symbol: "trash", size: 9.5, tint: Theme.text3, hit: 20, help: tr("Clear history")) { m.clearHistory() }
                    }
                }
                TextField("", text: $tm.input, prompt: Text(tr("12% of 80, 5 km to mi, sqrt(2)")).foregroundStyle(Theme.text3))
                    .textFieldStyle(.plain).font(Theme.mono(17, .semibold)).foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit {
                        if let r = m.commit() {
                            app.clipboard?.copy(text: r)
                            app.flash("checkmark.circle.fill", tr("Copied %@", r), tint: Theme.mint)
                        }
                    }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let r = m.result
                    Text(r == .failure ? (m.input.isEmpty ? " " : "…") : "= " + r.text)
                        .font(Theme.mono(22, .heavy)).foregroundStyle(Theme.blossom).lineLimit(1).minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                    Spacer()
                    if r != .failure {
                        IconButton(symbol: "doc.on.doc", size: 10.5, tint: Theme.text2, hit: 24, help: tr("Copy")) {
                            app.clipboard?.copy(text: r.text)
                            app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
                        }
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(m.history.prefix(8)) { h in
                            Button { m.input = h.input } label: {
                                HStack {
                                    Text(h.input).font(Theme.mono(11)).foregroundStyle(Theme.text3).lineLimit(1)
                                    Spacer()
                                    Text(h.result).font(Theme.mono(11, .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { if app.notch.focusSearch { focused = true; app.notch.focusSearch = false } }
    }
}
