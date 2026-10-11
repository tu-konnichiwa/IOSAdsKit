import Foundation

/// Platform clock driver: monotonic uptime, cancellable MainActor deadlines.
@MainActor
public final class SystemAdScheduler: AdScheduler {
    public init() {}
    public var now: Double { ProcessInfo.processInfo.systemUptime }

    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any AdCancellation {
        precondition(seconds.isFinite && seconds >= 0 && seconds <= 300, "Deadline must be in [0, 300] seconds")
        let task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return } // Cancellation removes the deadline; no result is owed by a clock.
            guard !Task.isCancelled else { return }
            action()
        }
        return ScheduledAdCancellation(task: task)
    }
}

@MainActor
private final class ScheduledAdCancellation: AdCancellation {
    private var task: Task<Void, Never>?
    init(task: Task<Void, Never>) { self.task = task }
    func cancel() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
