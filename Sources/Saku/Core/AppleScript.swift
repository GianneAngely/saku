import AppKit
import Carbon

/// Runs AppleScript off the main thread (one serial queue, one script object per call).
enum AppleScript {
    private static let queue = DispatchQueue(label: "saku.applescript", qos: .userInitiated)

    static func run(_ source: String, done: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("Saku AppleScript: \(error[NSAppleScript.errorMessage] ?? error)") }
            if let done {
                nonisolated(unsafe) let r = error == nil ? result : nil
                DispatchQueue.main.async { MainActor.assumeIsolated { done(r) } }
            }
        }
    }

    /// Quotes a Swift string for use inside an AppleScript string literal.
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    enum Permission { case granted, notAsked, denied, notRunning }

    /// Checks the Automation permission for an app without ever showing the prompt.
    static func permission(bundleID: String) -> Permission {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .notRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notAsked }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notAsked
        }
    }
}

extension NSAppleEventDescriptor {
    /// Items of a list result, 1-based in AppleScript, 0-based here.
    var items: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }
}
