import FichaCore
import FichaData
import Foundation
import Testing

struct CaptureTests {
    let time = ManualTimeSource(now: Date(timeIntervalSince1970: 1_760_000_000))

    @Test("a capture waits in the inbox with its text, note and source, and when it was captured")
    func captureWaitsInTheInbox() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try engine.capture(text: "serendipia", note: "Lo opuesto a buscar algo", source: "Un ensayo de Borges")

        let inbox = try engine.inbox()
        try #require(inbox.count == 1)
        #expect(inbox[0].text == "serendipia")
        #expect(inbox[0].note == "Lo opuesto a buscar algo")
        #expect(inbox[0].source == "Un ensayo de Borges")
        #expect(inbox[0].createdAt == Date(timeIntervalSince1970: 1_760_000_000))
    }

    // The capture window passes what each field holds, so a field left empty
    // arrives as a blank string.
    @Test("a capture is saved without surrounding spaces, and a blank note or source is left out")
    func blankNoteAndSourceAreLeftOut() throws {
        let engine = try Engine(location: .inMemory, time: time)

        try engine.capture(text: "  ubuntu\n", note: "", source: "   ")

        let inbox = try engine.inbox()
        try #require(inbox.count == 1)
        #expect(inbox[0].text == "ubuntu")
        #expect(inbox[0].note == nil)
        #expect(inbox[0].source == nil)
    }

    @Test("a capture with an empty text isn't saved")
    func emptyTextIsNotSaved() throws {
        let engine = try Engine(location: .inMemory, time: time)

        #expect(throws: EngineError.emptyCapture) {
            try engine.capture(text: " \n", note: "Una nota sin texto", source: nil)
        }
        #expect(try engine.inbox().isEmpty)
    }
}
