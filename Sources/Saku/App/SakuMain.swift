import AppKit

@main
struct SakuMain {
    @MainActor static var delegate: AppDelegate?

    @MainActor static func main() {
        let options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if !options.qa, let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != getpid() }) {
            // Already running: ask that copy to show its settings, then quit.
            DistributedNotificationCenter.default().postNotificationName(.init("local.saku.app.show"), object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            return
        }
        let app = NSApplication.shared
        let d = AppDelegate(options: options)
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
