import AppKit

/// Saku's own short sounds (Resources/Sounds, made by tools/make-sounds.py). QA runs are always muted.
@MainActor
enum Sound {
    static var muted = false
    private static var current: NSSound?

    static func url(_ name: String) -> URL? { AppResources.url("Sounds/\(name).wav") }

    static func play(_ name: String, volume: Double = 0.7) {
        guard !muted, let u = url(name), let s = NSSound(contentsOf: u, byReference: true) else { return }
        s.volume = Float(volume)
        current = s
        s.play()
    }
}
