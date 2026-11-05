import AppKit

@MainActor
enum OCRChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let img = NSImage(size: NSSize(width: 900, height: 220), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: NSColor.black]
            ("Saku notch 2026" as NSString).draw(at: CGPoint(x: 40, y: 120), withAttributes: a)
            ("Selamat pagi Bali" as NSString).draw(at: CGPoint(x: 40, y: 30), withAttributes: a)
            return true
        }
        var text: String?
        Task { @MainActor in text = await OCR.text(from: OCR.cgImage(img)!) }
        let until = Date().addingTimeInterval(20)
        while text == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        check(text?.contains("Saku notch 2026") == true, "reads English text (\(text?.replacingOccurrences(of: "\n", with: " / ") ?? "nil"))")
        check(text?.lowercased().contains("selamat pagi") == true, "reads Indonesian text")
        let blank = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { r in NSColor.white.setFill(); r.fill(); return true }
        var none: String?
        Task { @MainActor in none = await OCR.text(from: OCR.cgImage(blank)!) }
        while none == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        check(none == "", "a blank image has no text")
        check(OCR.isImage(path: "/a/b.PNG") && !OCR.isImage(path: "/a/b.pdf"), "image file check")
    }
}
