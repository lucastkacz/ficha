import Testing

// Fails on purpose, so the draft's `tests` check is seen red once, as the
// Makefile's header asks of a new check (#478). The next commit removes it.
struct TestsJobSeenFailingTests {
    @Test("the draft's tests job goes red when a test fails", .bug(id: 478))
    func failsOnPurpose() {
        Issue.record("Fails on purpose, to see the draft's tests job go red (#478).")
    }
}
