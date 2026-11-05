import Foundation

/// Where Saku keeps its files. QA runs point this at a scratch folder (`--data-dir`).
enum Paths {
    nonisolated(unsafe) static var dataDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Saku", isDirectory: true)
    }()

    static func file(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        return dataDir.appendingPathComponent(name)
    }

    static func folder(_ name: String) -> URL {
        let url = dataDir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// One Codable value in one JSON file, written atomically.
struct JSONStore<T: Codable> {
    let url: URL

    init(_ name: String) { url = Paths.file(name) }

    func load() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    func save(_ value: T) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Runs the last scheduled block after `delay` of quiet. Main thread only.
@MainActor final class Debouncer {
    private let delay: TimeInterval
    private var item: DispatchWorkItem?

    init(_ delay: TimeInterval) { self.delay = delay }

    func run(_ block: @escaping @MainActor () -> Void) {
        item?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { block() } }
        item = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func flush(_ block: @MainActor () -> Void) {
        item?.cancel()
        item = nil
        block()
    }
}
