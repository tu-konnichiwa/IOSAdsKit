import Testing
import IOSAdsKit

@Suite @MainActor
struct AdWaterfallTests {
    func make(_ loader: TestResourceLoader<String>, _ scheduler: TestScheduler,
              high: String? = "high", lifetime: Double = 60) throws -> AdWaterfall<String> {
        AdWaterfall(configuration: try AdLoadConfiguration(
            adUnitIDs: AdUnitIDs(highFloorAdUnitID: high, normalAdUnitID: "normal"),
            cacheLifetime: lifetime, loadTimeout: 5
        ), scheduler: scheduler, loader: loader.load)
    }

    @Test func highFloorSuccessDoesNotRequestNormal() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        var result: Result<String, AdsError>?
        waterfall.load { result = $0 }
        #expect(loader.requests.map(\.id) == ["high"])
        loader.complete(0, .success("high ad"))
        #expect(try result?.get() == "high ad")
        #expect(waterfall.state == .ready(.high))
        clock.advance(by: 100)
        #expect(loader.requests.count == 1)
    }

    @Test func highFloorFailureFallsBackOnceAndIgnoresLateCallbacks() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        var results: [Result<String, AdsError>] = []
        waterfall.load { results.append($0) }
        loader.complete(0, .failure(.loadFailed(message: "no fill")))
        #expect(loader.requests.map(\.id) == ["high", "normal"])
        loader.complete(0, .success("late high"))
        #expect(waterfall.state == .loading(.normal))
        loader.complete(1, .success("normal ad"))
        loader.complete(1, .success("duplicate"))
        #expect(results.count == 1)
        #expect(try results[0].get() == "normal ad")
        #expect(waterfall.state == .ready(.normal))
    }

    @Test func timeoutFallsBackThenTerminates() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        var result: Result<String, AdsError>?
        waterfall.load { result = $0 }
        clock.advance(by: 5)
        #expect(loader.requests.count == 2)
        #expect(loader.requests[0].token.cancelled)
        clock.advance(by: 5)
        #expect(result == .failure(.timedOut))
        #expect(waterfall.state == .failed(.timedOut))
        loader.complete(1, .success("late"))
        #expect(!waterfall.isReady)
    }

    @Test func normalOnlyAndFinalFailureCanRetry() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock, high: nil)
        waterfall.load()
        #expect(loader.requests.map(\.id) == ["normal"])
        loader.complete(0, .failure(.loadFailed(message: "offline")))
        #expect(waterfall.state == .failed(.loadFailed(message: "offline")))
        waterfall.load()
        loader.complete(1, .success("recovered"))
        #expect(waterfall.isReady)
    }

    @Test func concurrentLoadsCoalesceAndValidCacheIsReused() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        var results: [String] = []
        waterfall.load { if case .success(let ad) = $0 { results.append(ad) } }
        waterfall.load { if case .success(let ad) = $0 { results.append(ad) } }
        #expect(loader.requests.count == 1)
        loader.complete(0, .success("ad"))
        waterfall.load { if case .success(let ad) = $0 { results.append(ad) } }
        #expect(results == ["ad", "ad", "ad"])
        #expect(loader.requests.count == 1)
    }

    @Test func expiryAtBoundaryAndConsumptionRemoveCache() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        waterfall.load()
        loader.complete(0, .success("first"))
        clock.advance(by: 59)
        #expect(waterfall.isReady)
        clock.advance(by: 1)
        #expect(!waterfall.isReady)
        #expect(waterfall.state == .idle)
        waterfall.load()
        loader.complete(1, .success("second"))
        #expect(waterfall.takeReadyAd() == "second")
        #expect(waterfall.takeReadyAd() == nil)
    }

    @Test func invalidateCompletesAllCallersAndProtectsNewLoad() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        var results: [Result<String, AdsError>] = []
        waterfall.load { results.append($0) }
        waterfall.load { results.append($0) }
        waterfall.invalidate()
        #expect(results == [.failure(.cancelled), .failure(.cancelled)])
        waterfall.load()
        loader.complete(0, .failure(.loadFailed(message: "late failure")))
        #expect(loader.requests.count == 2)
        loader.complete(1, .success("new"))
        #expect(waterfall.takeReadyAd() == "new")
    }

    @Test func synchronousCompletionAndSynchronousCancellationAreSafe() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        loader.inlineResult = .failure(.loadFailed(message: "immediate"))
        let waterfall = try make(loader, clock)
        var count = 0
        waterfall.load { _ in count += 1 }
        #expect(count == 1)
        #expect(loader.requests.count == 2)
        #expect(loader.requests.allSatisfy { $0.token.cancelled })
        loader.inlineResult = nil
        waterfall.load()
        loader.requests[2].token.onCancel = { loader.complete(2, .success("cancel callback")) }
        waterfall.invalidate()
        #expect(waterfall.state == .idle)
        #expect(!waterfall.isReady)
    }

    @Test func cancellationNeverFallsBack() throws {
        let loader = TestResourceLoader<String>(), clock = TestScheduler()
        let waterfall = try make(loader, clock)
        waterfall.load()
        loader.complete(0, .failure(.cancelled))
        #expect(loader.requests.count == 1)
        #expect(waterfall.state == .failed(.cancelled))
    }
}
