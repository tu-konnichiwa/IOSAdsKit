public enum AdLoadState: Equatable, Sendable {
    case idle
    case loading(AdFloor)
    case ready(AdFloor)
    case failed(AdsError)
}

/// Shared high-floor/normal loading, deadlines, caching and stale-callback protection.
/// Keep the waterfall alive until requests finish. All access and callbacks use MainActor.
/// Concurrent load calls coalesce; invalidate completes every pending caller as cancelled.
@MainActor
public final class AdWaterfall<Resource> {
    public typealias Completion = @MainActor (Result<Resource, AdsError>) -> Void
    public typealias Loader = @MainActor (String, @escaping Completion) -> any AdCancellation

    private let configuration: AdLoadConfiguration
    private let scheduler: any AdScheduler
    private let loader: Loader
    private var storedState: AdLoadState = .idle
    private var cached: Resource?
    private var loadedAt: Double?
    private var callbacks: [Completion] = []
    private var request: (any AdCancellation)?
    private var deadline: (any AdCancellation)?
    private var generation: UInt64 = 0
    private var attemptIndex: Int?

    public init(configuration: AdLoadConfiguration, scheduler: any AdScheduler, loader: @escaping Loader) {
        self.configuration = configuration
        self.scheduler = scheduler
        self.loader = loader
    }

    /// Reading state discards expired cache; equality at expiry counts as expired.
    public var state: AdLoadState { expireIfNeeded(); return storedState }
    public var isReady: Bool { expireIfNeeded(); return cached != nil }

    public func load(completion: @escaping Completion = { _ in }) {
        expireIfNeeded()
        if let cached { completion(.success(cached)); return }
        callbacks.append(completion)
        guard attemptIndex == nil else { return }
        generation &+= 1
        startAttempt(index: 0, generation: generation)
    }

    /// Transfers ownership of a ready resource and removes it from the cache.
    public func takeReadyAd() -> Resource? {
        expireIfNeeded()
        let result = cached
        cached = nil
        loadedAt = nil
        if attemptIndex == nil { storedState = .idle }
        return result
    }

    /// Cancels logical loading (SDK network work may continue) and clears cache.
    public func invalidate() {
        generation &+= 1
        attemptIndex = nil
        let oldRequest = request
        let oldDeadline = deadline
        request = nil
        deadline = nil
        cached = nil
        loadedAt = nil
        storedState = .idle
        let pending = callbacks
        callbacks.removeAll()
        oldDeadline?.cancel()
        oldRequest?.cancel()
        pending.forEach { $0(.failure(.cancelled)) }
    }

    private func expireIfNeeded() {
        guard let loadedAt, scheduler.now - loadedAt >= configuration.cacheLifetime else { return }
        cached = nil
        self.loadedAt = nil
        storedState = .idle
    }

    private func startAttempt(index: Int, generation current: UInt64) {
        let attempt = configuration.adUnitIDs.attempts[index]
        attemptIndex = index
        storedState = .loading(attempt.floor)
        deadline = scheduler.schedule(after: configuration.loadTimeout) { [weak self] in
            self?.receive(.failure(.timedOut), index: index, generation: current)
        }
        let token = loader(attempt.adUnitID) { [weak self] result in
            self?.receive(result, index: index, generation: current)
        }
        // A driver is allowed to complete inline, including failing into fallback.
        if generation == current, attemptIndex == index { request = token }
        else { token.cancel() }
    }

    private func receive(_ result: Result<Resource, AdsError>, index: Int, generation current: UInt64) {
        guard generation == current, attemptIndex == index else { return }
        attemptIndex = nil
        let oldRequest = request
        let oldDeadline = deadline
        request = nil
        deadline = nil
        // Invalidate this attempt before cancellation can synchronously call back.
        generation &+= 1
        oldDeadline?.cancel()
        oldRequest?.cancel()
        switch result {
        case .success(let resource):
            cached = resource
            loadedAt = scheduler.now
            storedState = .ready(configuration.adUnitIDs.attempts[index].floor)
            finish(.success(resource))
        case .failure(let error):
            if error != .cancelled, index + 1 < configuration.adUnitIDs.attempts.count {
                startAttempt(index: index + 1, generation: generation)
            } else {
                storedState = .failed(error)
                finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<Resource, AdsError>) {
        let pending = callbacks
        callbacks.removeAll()
        pending.forEach { $0(result) }
    }
}
