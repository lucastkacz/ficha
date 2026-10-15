import FichaCore
import Testing

/// Tests on when the review panel of an appearance takes the keyboard, so it
/// doesn't catch what Lucas is typing in another app (#10's findings).
struct FocusModeTests {
    @Test(
        "the panel takes the keyboard as the focus mode says: never, once Lucas has been idle for 5 seconds, or always",
        arguments: [
            (FocusMode.never, Duration.seconds(60), false),
            (.onceIdle, .milliseconds(4_999), false),
            (.onceIdle, .seconds(5), true),
            (.always, .zero, true),
        ]
    )
    func takesTheKeyboardAsTheFocusModeSays(mode: FocusMode, idle: Duration, takesIt: Bool) {
        #expect(mode.takesKeyboard(idle: idle, after: .seconds(5)) == takesIt)
    }

    // Without the idle time, the panel can't tell whether Lucas is typing, so
    // it stays out of his way.
    @Test("once idle, the panel doesn't take the keyboard when the Mac doesn't say how long Lucas has been idle")
    func onceIdleWaitsForTheIdleTime() {
        #expect(!FocusMode.onceIdle.takesKeyboard(idle: nil, after: .seconds(5)))
    }
}
