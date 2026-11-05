import AppKit

@MainActor
enum NotesChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let m = app.notes!
        check(!m.notes.isEmpty && m.current != nil, "a first note exists")
        let n = m.add("# Groceries\nMilk\nMatcha")
        check(m.current?.id == n.id, "new note is selected")
        check(m.current?.title == "Groceries" && m.current?.preview == "Milk", "title and preview from the text")
        m.update(n.id, text: "Ideas\nnotch pet")
        check(m.sorted.first?.id == n.id, "edited note goes to the top")
        let other = m.add("Older")
        m.togglePin(n.id)
        check(m.sorted.first?.id == n.id, "pinned notes stay first")
        check(Note(text: "one two\nthree").words == 3, "word count")
        let empty = m.add()
        m.removeEmpty()
        check(!m.notes.contains { $0.id == empty.id }, "empty notes are cleaned up")
        m.saveNow()
        check(JSONStore<[Note]>("notes.json").load()?.count == m.notes.count, "notes are saved")
        m.delete(other.id)
        check(!m.notes.contains { $0.id == other.id }, "delete")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-notes", settle: 0.5) { app in
            let m = app.notes!
            for n in m.notes { m.delete(n.id) }
            m.add("Cake Tower update\nAdd a pause menu, fix the stacking wobble, new sakura skin.")
            m.add("Teleprompter script ideas\nIntro, what Saku does, three favourite features.")
            let main = m.add("Notch app checklist\n- music card ✓\n- timers ✓\n- tray and AirDrop ✓\n- clipboard ✓\n- teleprompter next")
            m.removeEmpty()
            m.selected = main.id
            app.notch.mode = .open
            app.notch.tab = .notes
        },
    ]
}
