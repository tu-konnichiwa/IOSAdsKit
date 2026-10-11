import IOSAdsKit

@MainActor
final class TestCancellation: AdCancellation {
    private(set) var cancelled = false
    var onCancel: (() -> Void)?
    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel?()
    }
}

@MainActor
final class TestScheduler: AdScheduler {
    struct Deadline {
        let time: Double
        let token: TestCancellation
        let action: @MainActor () -> Void
    }
    var now: Double = 0
    private var deadlines: [Deadline] = []
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any AdCancellation {
        let token = TestCancellation()
        deadlines.append(Deadline(time: now + seconds, token: token, action: action))
        return token
    }
    func advance(by seconds: Double) {
        let target = now + seconds
        while let next = deadlines.enumerated().filter({ !$0.element.token.cancelled && $0.element.time <= target })
            .min(by: { $0.element.time < $1.element.time }) {
            deadlines.remove(at: next.offset)
            now = next.element.time
            next.element.action()
        }
        now = target
    }
}

@MainActor
final class TestResourceLoader<Resource> {
    struct Request {
        let id: String
        let token: TestCancellation
        let completion: AdWaterfall<Resource>.Completion
    }
    var requests: [Request] = []
    var inlineResult: Result<Resource, AdsError>?
    func load(_ id: String, completion: @escaping AdWaterfall<Resource>.Completion) -> any AdCancellation {
        let token = TestCancellation()
        requests.append(Request(id: id, token: token, completion: completion))
        if let inlineResult { completion(inlineResult) }
        return token
    }
    // Intentionally allows late callbacks after cancellation to test stale-request isolation.
    func complete(_ index: Int, _ result: Result<Resource, AdsError>) { requests[index].completion(result) }
}

@MainActor
final class TestFullScreenLoader: FullScreenAdLoading {
    struct Request {
        let format: FullScreenAdFormat
        let id: String
        let completion: @MainActor (Result<any FullScreenAd, AdsError>) -> Void
        let token: TestCancellation
    }
    var requests: [Request] = []
    func load(format: FullScreenAdFormat, adUnitID: String,
              completion: @escaping @MainActor (Result<any FullScreenAd, AdsError>) -> Void) -> any AdCancellation {
        let token = TestCancellation()
        requests.append(Request(format: format, id: adUnitID, completion: completion, token: token))
        return token
    }
    @discardableResult
    func succeed(_ index: Int) -> TestFullScreenAd {
        let ad = TestFullScreenAd()
        requests[index].completion(.success(ad))
        return ad
    }
}

@MainActor
final class TestFullScreenAd: FullScreenAd {
    private var callback: (@MainActor (FullScreenAdEvent) -> Void)?
    var inlineEvents: [FullScreenAdEvent] = []
    func present(onEvent: @escaping @MainActor (FullScreenAdEvent) -> Void) {
        callback = onEvent
        inlineEvents.forEach(onEvent)
    }
    func emit(_ event: FullScreenAdEvent) { callback?(event) }
}
