import Testing
import IOSAdsKit

@Suite @MainActor
struct SystemAdSchedulerTests {
    @Test func zeroDeadlineEnqueuesAndCancellationIsIdempotent() async {
        let clock = SystemAdScheduler()
        let start = clock.now
        var cancelledActionRan = false
        let cancelled = clock.schedule(after: 0) { cancelledActionRan = true }
        cancelled.cancel()
        cancelled.cancel()
        var deadline: (any AdCancellation)?
        await withCheckedContinuation { continuation in
            deadline = clock.schedule(after: 0) {
                continuation.resume()
            }
            #expect(clock.now >= start)
            #expect(!cancelledActionRan)
        }
        #expect(!cancelledActionRan)
        deadline?.cancel()
    }
}
