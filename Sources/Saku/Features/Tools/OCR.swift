import AppKit
import SwiftUI
@preconcurrency import Vision

/// Text from images with Vision, fully on this Mac.
enum OCR {
    static func text(from image: CGImage) async -> String {
        await withCheckedContinuation { c in
            let req = VNRecognizeTextRequest { r, _ in
                let lines = (r.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                c.resume(returning: lines.joined(separator: "\n"))
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.automaticallyDetectsLanguage = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([req])
                } catch {
                    c.resume(returning: "")
                }
            }
        }
    }

    static func cgImage(_ ns: NSImage) -> CGImage? {
        var r = CGRect(origin: .zero, size: ns.size)
        return ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
    }

    /// Reads the text, copies it, and says what happened in the notch.
    @MainActor static func copyText(from ns: NSImage?, app: AppModel) {
        guard let ns, let cg = cgImage(ns) else { return }
        app.flash("text.viewfinder", tr("Reading text…"), tint: Theme.lavender, seconds: 6)
        Task { @MainActor in
            let t = await text(from: cg)
            if t.isEmpty {
                app.flash("text.viewfinder", tr("No text found"), tint: Theme.butter)
            } else {
                app.clipboard?.copy(text: t)
                app.flash("checkmark.circle.fill", tr("Copied %d characters", t.count), tint: Theme.mint)
            }
        }
    }

    static func isImage(path: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"].contains((path as NSString).pathExtension.lowercased())
    }
}
