import FichaCore
import Foundation
import Testing

struct CardStandingTests {
    @Test("a card neither flagged, buried nor set aside is in Lucas's reviews")
    func neitherFlaggedBuriedNorSetAsideIsInReviews() {
        #expect(CardStanding(flag: nil, buriedAt: nil, setAsideBy: []) == .inReviews)
    }

    @Test("a flagged card waits in the inbox, with its flag")
    func flaggedWaitsInInbox() {
        #expect(CardStanding(flag: flag, buriedAt: nil, setAsideBy: []) == .inInbox(flag))
    }

    @Test("a buried card is buried, and a flagged buried card is buried and keeps its flag")
    func buriedIsBuried() {
        #expect(CardStanding(flag: nil, buriedAt: buriedAt, setAsideBy: []) == .buried(at: buriedAt, flag: nil))
        #expect(CardStanding(flag: flag, buriedAt: buriedAt, setAsideBy: []) == .buried(at: buriedAt, flag: flag))
    }

    @Test("a card in a set-aside deck is set aside rather than in Lucas's reviews")
    func setAsideWinsOverReviews() {
        #expect(CardStanding(flag: nil, buriedAt: nil, setAsideBy: ["filosofía"]) == .setAside(by: ["filosofía"]))
    }

    @Test("a flagged card in a set-aside deck waits in the inbox")
    func theInboxWinsOverSetAside() {
        #expect(CardStanding(flag: flag, buriedAt: nil, setAsideBy: ["filosofía"]) == .inInbox(flag))
    }

    @Test("a buried card in a set-aside deck is buried, and keeps its flag")
    func buriedWinsOverSetAside() {
        #expect(
            CardStanding(flag: nil, buriedAt: buriedAt, setAsideBy: ["filosofía"]) == .buried(at: buriedAt, flag: nil))
        #expect(
            CardStanding(flag: flag, buriedAt: buriedAt, setAsideBy: ["filosofía"]) == .buried(at: buriedAt, flag: flag)
        )
    }

    @Test("a card's set-aside decks are its deck and the decks it sits inside that are set aside, the outermost first")
    func setAsideDecksAreTheCardsDeckAndThoseItSitsInside() {
        let setAsideDecks: Set = ["Idiomas", "Idiomas::Inglés::Verbos", "Historia", "Idiomas::Francés"]

        #expect(
            CardStanding.setAsideDecks(of: "Idiomas::Inglés::Verbos", among: setAsideDecks)
                == ["Idiomas", "Idiomas::Inglés::Verbos"])
        #expect(CardStanding.setAsideDecks(of: "Idiomas::Inglés", among: setAsideDecks) == ["Idiomas"])
        #expect(CardStanding.setAsideDecks(of: "Historia Argentina", among: setAsideDecks).isEmpty)
        #expect(CardStanding.setAsideDecks(of: "", among: setAsideDecks).isEmpty)
        #expect(CardStanding.setAsideDecks(of: "", among: [""]) == [""])
    }

    @Test(
        "a card is due only in Lucas's reviews: flagged, buried or set aside, it has no due time even once its wait is over"
    )
    func dueOnlyInReviews() {
        let started = WayStanding.started(.graduated, interval: .days(5), due: start, memory: nil)
        let later = start.addingTimeInterval(60)

        #expect(CardStanding.inReviews.due(given: started) == start)
        #expect(CardStanding.inReviews.isDue(at: later, given: started))
        for outOfReviews in [CardStanding.inInbox(flag), .buried(at: buriedAt, flag: nil), .setAside(by: ["historia"])]
        {
            #expect(outOfReviews.due(given: started) == nil)
            #expect(!outOfReviews.isDue(at: later, given: started))
        }
    }

    @Test("a card is new or learned only in Lucas's reviews: not while it's flagged, buried or set aside")
    func newOrLearnedOnlyInReviews() {
        let learned = WayStanding.started(.graduated, interval: .days(21), due: start, memory: nil)

        #expect(CardStanding.inReviews.isNew(given: .new))
        #expect(CardStanding.inReviews.isLearned(given: learned))
        for outOfReviews in [
            CardStanding.inInbox(flag), .buried(at: buriedAt, flag: flag), .setAside(by: ["historia"]),
        ] {
            #expect(!outOfReviews.isNew(given: .new))
            #expect(!outOfReviews.isLearned(given: learned))
        }
    }

    @Test(
        "a way is learned once it graduated with an interval of 21 days or more, as Anki's mature cards, and not while it relearns"
    )
    func learnedFrom21Days() {
        let graduatedFor20Days = WayStanding.started(.graduated, interval: .days(20), due: start, memory: nil)
        let graduatedFor21Days = WayStanding.started(.graduated, interval: .days(21), due: start, memory: nil)
        let relearning = WayStanding.started(.relearning(step: 0), interval: .days(30), due: start, memory: nil)

        #expect(!CardStanding.inReviews.isLearned(given: graduatedFor20Days))
        #expect(CardStanding.inReviews.isLearned(given: graduatedFor21Days))
        #expect(!CardStanding.inReviews.isLearned(given: relearning))
        #expect(!CardStanding.inReviews.isLearned(given: .new))
    }
}

// The hour, the day and the start these tests count from are the scheduler's
// tests', in SchedulerFixtures.swift.
private let flag = Flag(note: "Falta un ejemplo", flaggedAt: start.addingTimeInterval(-3_600))
private let buriedAt = start.addingTimeInterval(-60)
