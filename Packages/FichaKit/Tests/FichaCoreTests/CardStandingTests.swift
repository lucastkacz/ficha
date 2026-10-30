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

    @Test("a card with a set-aside tag is set aside rather than in Lucas's reviews")
    func setAsideWinsOverReviews() {
        #expect(CardStanding(flag: nil, buriedAt: nil, setAsideBy: ["filosofía"]) == .setAside(by: ["filosofía"]))
    }

    @Test("a flagged card with a set-aside tag waits in the inbox")
    func theInboxWinsOverSetAside() {
        #expect(CardStanding(flag: flag, buriedAt: nil, setAsideBy: ["filosofía"]) == .inInbox(flag))
    }

    @Test("a buried card with a set-aside tag is buried, and keeps its flag")
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
        let onLadder = LadderStanding.onLadder(step: 2, due: start)
        let later = start.addingTimeInterval(60)

        #expect(CardStanding.inReviews.due(given: onLadder) == start)
        #expect(CardStanding.inReviews.isDue(at: later, given: onLadder))
        for outOfReviews in [CardStanding.inInbox(flag), .buried(at: buriedAt, flag: nil), .setAside(by: ["historia"])]
        {
            #expect(outOfReviews.due(given: onLadder) == nil)
            #expect(!outOfReviews.isDue(at: later, given: onLadder))
        }
    }

    @Test("a card is new or learned only in Lucas's reviews: not while it's flagged, buried or set aside")
    func newOrLearnedOnlyInReviews() {
        let ladder = Ladder.standard
        // The standard ladder's sixth step waits 30 days.
        let learned = LadderStanding.onLadder(step: 5, due: start)

        #expect(CardStanding.inReviews.isNew(given: .new))
        #expect(CardStanding.inReviews.isLearned(given: learned, on: ladder))
        for outOfReviews in [
            CardStanding.inInbox(flag), .buried(at: buriedAt, flag: flag), .setAside(by: ["historia"]),
        ] {
            #expect(!outOfReviews.isNew(given: .new))
            #expect(!outOfReviews.isLearned(given: learned, on: ladder))
        }
    }

    // Once Ficha syncs, a card's review log joins what the Mac and the iPhone
    // each recorded without a connection (ADR 0017): here each rated the wait
    // the placement started.
    @Test("a card two devices rated “Know it” for one wait is due one step up, counted from the first rating")
    func twoKnowItsForOneWaitMakeTheCardDueOneStepUp() throws {
        // An import placed the card on the standard ladder's fifth step, which
        // waits 12 days; the sixth waits 30 days, from which a card is learned.
        let placed = ReviewLogEntry(placing: 1, on: Placement(step: 4, due: start), at: start - 12 * day, uuid: UUID())
        let onTheMac = ReviewLogEntry(
            cardID: 1, kind: .review(.good), answeredAt: start, responseTime: .seconds(3), trigger: .reviewNow,
            uuid: UUID(), answeredEntry: placed.uuid)
        let onTheIPhone = ReviewLogEntry(
            cardID: 1, kind: .review(.good), answeredAt: start.addingTimeInterval(2 * hour), responseTime: .seconds(3),
            trigger: .reviewNow, uuid: UUID(), answeredEntry: placed.uuid)

        let standing = try Ladder.standard.standing(after: [placed, onTheMac, onTheIPhone])

        #expect(CardStanding.inReviews.due(given: standing) == start.addingTimeInterval(30 * day))
        #expect(CardStanding.inReviews.isLearned(given: standing, on: .standard))
    }
}

private let hour: TimeInterval = 60 * 60
private let day: TimeInterval = 24 * hour
private let start = Date(timeIntervalSince1970: 1_760_000_000)
private let flag = Flag(note: "Falta un ejemplo", flaggedAt: start.addingTimeInterval(-3_600))
private let buriedAt = start.addingTimeInterval(-60)
