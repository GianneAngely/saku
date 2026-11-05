import AppKit

@MainActor
enum AirDropChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        var sent: [URL] = []
        let real = AirDrop.sender
        AirDrop.sender = { urls in sent = urls; return true }
        defer { AirDrop.sender = real }

        let files = TrayChecks.sampleFiles()
        check(AirDrop.send(DropPayload(files: files, links: [URL(string: "https://x.dev")!])), "files go to AirDrop")
        check(sent == files, "only the files are sent")
        sent = []
        check(!AirDrop.send(DropPayload(texts: ["hi"])), "text alone is refused")
        check(sent.isEmpty, "nothing sent for text")
        app.handleDrop(DropPayload(files: [files[0]]), zone: .airdrop)
        check(sent == [files[0]], "dropping on the AirDrop zone sends the file")
        app.handleDrop(DropPayload(texts: ["only text"]), zone: .airdrop)
        check(app.notch.hud?.text == tr("AirDrop takes files only"), "a friendly note when there is no file")
        app.notch.hud = nil
        check(AirDrop.isAvailable, "AirDrop sharing service exists on this Mac")
    }
}
