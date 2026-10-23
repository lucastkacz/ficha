import FichaCore
import Foundation
import Testing

struct CardStandingTests {
    @Test("a card neither flagged nor buried is in Lucas's reviews")
    func neitherFlaggedNorBuriedIsInReviews() {
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

    @Test("a set-aside card's set-aside tags come in alphabetical order, as the Mac sorts text")
    func setAsideTagsComeAlphabetically() {
        #expect(
            CardStanding(flag: nil, buriedAt: nil, setAsideBy: ["lenguaje", "Ética", "filosofía"])
                == .setAside(by: ["Ética", "filosofía", "lenguaje"]))
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
}

private let start = Date(timeIntervalSince1970: 1_760_000_000)
private let flag = Flag(note: "Falta un ejemplo", flaggedAt: start.addingTimeInterval(-3_600))
private let buriedAt = start.addingTimeInterval(-60)
