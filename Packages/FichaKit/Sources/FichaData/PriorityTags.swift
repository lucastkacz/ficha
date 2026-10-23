import FichaCore
import Foundation
internal import GRDB

extension Engine {
    /// Toggles `tag`'s priority: a priority tag is no longer one, and a tag
    /// that's neither a priority tag nor set aside becomes one, so its cards
    /// come first from the next appearance, review now or "See more" on. A
    /// set-aside tag stays set aside, since a tag is never both (ADR 0011):
    /// the Prioritize submenu doesn't offer it.
    public func togglePriority(of tag: String) throws(EngineError) {
        try write { db in
            var own = try tagsWithSomethingOfTheirOwn(in: db)[tag] ?? CardTag(name: tag)
            switch own.switchedOn {
            case .priority: own.switchedOn = nil
            case nil: own.switchedOn = .priority
            case .setAside: return
            }
            try save(own, in: db)
        }
    }
}
