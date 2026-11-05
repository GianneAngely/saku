import Foundation
import Observation

/// App language. Every UI string goes through `tr("English")`; Bahasa Indonesia comes from `Indonesian.table`.
/// Reading `code` inside a view body registers it with Observation, so switching language redraws at once.
@Observable
final class Lang: @unchecked Sendable {
    static let shared = Lang()
    var code = "system"

    var isIndonesian: Bool {
        switch code {
        case "id": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("id") ?? false
        }
    }
}

func tr(_ english: String) -> String {
    guard Lang.shared.isIndonesian else { return english }
    return Indonesian.table[english] ?? english
}

/// `tr` with %@ / %d placeholders filled in order.
func tr(_ english: String, _ args: CVarArg...) -> String {
    String(format: tr(english), arguments: args)
}
