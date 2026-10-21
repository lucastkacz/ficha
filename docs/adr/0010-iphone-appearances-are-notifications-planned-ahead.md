# On the iPhone, appearances are local notifications planned ahead

On the Mac, Ficha checks every minute whether an appearance is due and shows the review panel. The iPhone app can't: iOS doesn't let an app wake itself up at a time it picks, and push notifications need a server, which ADR 0001 leaves out, and the paid Apple Developer membership. So the engine plans the upcoming appearances with the Mac's rules, as if nothing were rated in between, and the app schedules them as local notifications, which iOS delivers on its own. Nothing changes the cards while the app isn't running, so the plan stays exact until Lucas does something, and whatever he does plans again.

## Considered options

- Background refresh, to check for appearances as the Mac does: iOS decides when it runs, if ever, so appearances would come late or not at all.
- One identifier for every notification, so that a new one replaces the one before and the lock screen holds at most one, as #97 first asked: iOS keeps one pending notification per identifier, so only the next appearance would be scheduled, and none would come after it until the app runs again.

## Consequences

- The app plans again whenever the engine's data changes, the settings or the debug time change, and the app opens or comes back to the foreground.
- iOS keeps at most 64 notifications pending for an app, so the plan stops one short of them and covers as far ahead as fits. When it runs out before Lucas opens the app or acts on a notification, appearances stop until he does.
- Each pending notification has an identifier of its own, and they all go in one thread: while Lucas leaves them alone, the notifications that arrive pile up in one stack on the lock screen, until the app plans again and clears them.
- While the app is in front, iOS doesn't show its notifications, so an appearance due then doesn't show, and the next one comes after the separation.
- Waking, idle time and suppressions don't apply on the iPhone: iOS's Focus silences notifications on its own.
