import Foundation
import Testing

// Never lands: #330's PR shows `make check` failing on it, within the watchdog's
// two minutes, saying where it hung.
@Test("a test that waits on a semaphore nobody signals hangs the run")
func hangsOnPurpose() {
    DispatchSemaphore(value: 0).wait()
}
