import Testing
import IOSAdsKit

@Suite @MainActor
struct FullScreenAdsTests {
    func configuration(
        _ format: FullScreenAdFormat = .interstitial,
        refresh: AdRefreshPolicy = .manual, minimumInterval: Double = 10,
        background: Double = 0, cold: Bool = true
    ) throws -> FullScreenAdConfiguration {
        try FullScreenAdConfiguration(
            format: format, adUnitIDs: AdUnitIDs(highFloorAdUnitID: "high", normalAdUnitID: "normal"),
            refreshPolicy: refresh, minimumInterval: minimumInterval,
            minimumBackgroundDuration: background, allowsColdStart: cold
        )
    }

    @Test func disabledUnknownExcludedAndNotReadyAreExplicit() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration()], loader: loader, scheduler: clock)
        var results: [AdShowResult] = []
        ads.show(.common) { results.append($0) }
        ads.load(.common)
        #expect(loader.requests.isEmpty)
        ads.setAdsEnabled(true)
        ads.show("unknown") { results.append($0) }
        ads.show(.common, excluded: true) { results.append($0) }
        ads.show(.common) { results.append($0) }
        #expect(loader.requests.count == 1)
        #expect(results == [.skipped(.adsDisabled), .skipped(.unknownPlacement), .skipped(.excluded), .skipped(.notReady)])
    }

    @Test func highFloorFallbackAlsoWorksForFullScreenFormats() throws {
        for format in [FullScreenAdFormat.interstitial, .appOpen, .rewarded] {
            let loader = TestFullScreenLoader(), clock = TestScheduler()
            let ads = FullScreenAds(placements: [.common: try configuration(format)], loader: loader, scheduler: clock, adsEnabled: true)
            var completed = false
            ads.load(.common) { if case .success = $0 { completed = true } }
            loader.requests[0].completion(.failure(.loadFailed(message: "high no fill")))
            #expect(loader.requests.map(\.id) == ["high", "normal"])
            #expect(loader.requests.allSatisfy { $0.format == format })
            loader.succeed(1)
            #expect(completed)
            #expect(ads.isAvailable(.common))
        }
    }

    @Test func sharedPresentationLockPreventsCrossFormatOverlap() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [
            .common: try configuration(), .appOpen: try configuration(.appOpen)
        ], loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let interstitial = loader.succeed(0)
        ads.load(.appOpen)
        let appOpen = loader.succeed(1)
        var results: [AdShowResult] = []
        ads.show(.common) { results.append($0) }
        ads.show(.appOpen) { results.append($0) }
        #expect(ads.isPresenting)
        #expect(ads.isAvailable(.appOpen))
        interstitial.emit(.presented)
        interstitial.emit(.dismissed)
        interstitial.emit(.dismissed)
        #expect(!ads.isPresenting)
        ads.show(.appOpen) { results.append($0) }
        appOpen.emit(.dismissed)
        #expect(results == [.skipped(.alreadyPresenting), .dismissed, .dismissed])
    }

    @Test func frequencyIsSharedAcrossPlacementsAndMeasuredAtPresentation() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [
            .common: try configuration(), .splash: try configuration()
        ], loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let first = loader.succeed(0)
        ads.load(.splash)
        let second = loader.succeed(1)
        ads.show(.common) { _ in }
        first.emit(.presented)
        clock.advance(by: 9)
        first.emit(.dismissed)
        var result: AdShowResult?
        ads.show(.splash) { result = $0 }
        #expect(result == .skipped(.frequencyCapped))
        #expect(ads.isAvailable(.splash))
        clock.advance(by: 1)
        ads.show(.splash) { result = $0 }
        second.emit(.presented)
        second.emit(.dismissed)
        #expect(result == .dismissed)
    }

    @Test func bypassDoesNotBypassExclusionOrPresentationLock() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration(refresh: .afterPresentation)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let first = loader.succeed(0)
        ads.show(.common) { _ in }
        first.emit(.presented)
        first.emit(.dismissed)
        let next = loader.succeed(1)
        var result: AdShowResult?
        ads.show(.common, excluded: true, bypassInterval: true) { result = $0 }
        #expect(result == .skipped(.excluded))
        ads.show(.common, bypassInterval: true) { result = $0 }
        #expect(ads.isPresenting)
        ads.show(.common, bypassInterval: true) { result = $0 }
        #expect(result == .skipped(.alreadyPresenting))
        next.emit(.dismissed)
        #expect(result == .dismissed)
    }

    @Test func presentationFailureCompletesOnceAndAutoReloads() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration(refresh: .afterPresentation)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let first = loader.succeed(0)
        first.inlineEvents = [.failed(.presentationFailed(message: "invalid presenter")), .dismissed]
        var results: [AdShowResult] = []
        ads.show(.common) { results.append($0) }
        #expect(results == [.failed(.presentationFailed(message: "invalid presenter"))])
        #expect(!ads.isPresenting)
        #expect(loader.requests.count == 2)
        let next = loader.succeed(1)
        ads.show(.common) { results.append($0) }
        #expect(ads.isPresenting) // Failure before presenting must not consume frequency allowance.
        next.emit(.dismissed)
    }

    @Test func rewardedReportsOnlyEarnedRewardOnce() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration(.rewarded)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let ad = loader.succeed(0)
        let reward = AdReward(amount: 5, type: "credits")
        var rewards: [AdReward] = []
        var results: [AdShowResult] = []
        ads.show(.common, onReward: { rewards.append($0) }) { results.append($0) }
        ad.emit(.earnedReward(reward))
        ad.emit(.earnedReward(reward))
        ad.emit(.dismissed)
        ad.emit(.earnedReward(reward))
        #expect(rewards == [reward])
        #expect(results == [.dismissed])
        ads.load(.common)
        let noReward = loader.succeed(1)
        ads.show(.common, onReward: { rewards.append($0) }) { results.append($0) }
        noReward.emit(.dismissed)
        #expect(rewards == [reward])
        #expect(results == [.dismissed, .dismissed])
    }

    @Test func appOpenHonorsBackgroundColdStartAndExpiry() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.appOpen: try configuration(.appOpen, background: 30, cold: false)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.appOpen)
        let ad = loader.succeed(0)
        var result: AdShowResult?
        ads.show(.appOpen) { result = $0 }
        #expect(result == .skipped(.coldStartDisabled))
        ads.recordBackground()
        clock.advance(by: 29)
        ads.show(.appOpen) { result = $0 }
        #expect(result == .skipped(.backgroundTooShort))
        clock.advance(by: 1)
        ads.show(.appOpen) { result = $0 }
        ad.emit(.presented)
        ads.recordBackground() // Ignore lifecycle effects from the visible ad.
        ad.emit(.dismissed)
        #expect(result == .dismissed)
        ads.load(.appOpen)
        loader.succeed(1)
        clock.advance(by: 14_400)
        #expect(!ads.isAvailable(.appOpen))
    }

    @Test func disablingCancelsCacheAndPendingLoadsButVisibleAdFinishes() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration(refresh: .afterPresentation)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        var loadResults: [Result<Void, AdsError>] = []
        ads.load(.common) { loadResults.append($0) }
        ads.setAdsEnabled(false)
        #expect(loadResults.count == 1)
        if case .failure(let error) = loadResults[0] { #expect(error == .cancelled) }
        else { Issue.record("Expected cancellation") }
        loader.succeed(0)
        #expect(!ads.isAvailable(.common))
        ads.setAdsEnabled(true)
        ads.load(.common)
        let ad = loader.succeed(1)
        var showResult: AdShowResult?
        ads.show(.common) { showResult = $0 }
        ads.setAdsEnabled(false)
        ad.emit(.dismissed)
        #expect(showResult == .dismissed)
        #expect(loader.requests.count == 2) // Auto refresh is suppressed while disabled.
    }

    @Test func loadWhileShowingAndClearDoNotLosePresentationCompletion() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration()], loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let ad = loader.succeed(0)
        var results: [AdShowResult] = []
        ads.show(.common) { results.append($0) }
        ads.load(.common)
        ads.clear(.common)
        ad.emit(.dismissed)
        #expect(results == [.dismissed])
    }

    @Test func terminalCallbackCanReenterAndOldEventsCannotFinishNewAd() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration(minimumInterval: 0)],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let first = loader.succeed(0)
        var count = 0
        ads.show(.common) { _ in
            count += 1
            ads.show(.common) { _ in count += 1 }
        }
        ads.load(.common)
        let second = loader.succeed(1)
        first.emit(.dismissed)
        #expect(ads.isPresenting)
        first.emit(.failed(.presentationFailed(message: "stale")))
        #expect(ads.isPresenting)
        second.emit(.dismissed)
        #expect(count == 2)
    }
    @Test func preloadAndUnknownPlacementExposeLoadOutcomes() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration()],
                                loader: loader, scheduler: clock, adsEnabled: true)
        #expect(ads.loadState(for: "unknown") == nil)
        var failure: AdsError?
        ads.load("unknown") { if case .failure(let error) = $0 { failure = error } }
        #expect(failure == .invalidConfiguration("Unknown placement: unknown"))
        ads.preloadAll()
        #expect(loader.requests.count == 1)
        #expect(ads.loadState(for: .common) == .loading(.high))
        loader.succeed(0)
        #expect(ads.loadState(for: .common) == .ready(.high))
    }

    @Test func duplicatePresentedDoesNotExtendFrequencyAndNonRewardedIgnoresReward() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        let ads = FullScreenAds(placements: [.common: try configuration()],
                                loader: loader, scheduler: clock, adsEnabled: true)
        ads.load(.common)
        let first = loader.succeed(0)
        var rewards = 0
        ads.show(.common, onReward: { _ in rewards += 1 }) { _ in }
        first.emit(.presented)
        clock.advance(by: 9)
        first.emit(.presented)
        first.emit(.earnedReward(AdReward(amount: 1, type: "invalid format")))
        first.emit(.dismissed)
        ads.load(.common)
        let next = loader.succeed(1)
        clock.advance(by: 1)
        ads.show(.common) { _ in }
        #expect(ads.isPresenting)
        #expect(rewards == 0)
        next.emit(.dismissed)
    }

    @Test func visibleResourceAndClientHaveNoRetainCycle() throws {
        let loader = TestFullScreenLoader(), clock = TestScheduler()
        var ads: FullScreenAds? = FullScreenAds(placements: [.common: try configuration()],
                                               loader: loader, scheduler: clock, adsEnabled: true)
        weak var weakAds = ads
        ads?.load(.common)
        var resource: TestFullScreenAd? = loader.succeed(0)
        weak var weakResource = resource
        ads?.show(.common) { _ in }
        resource = nil
        #expect(weakResource != nil)
        weakResource?.emit(.dismissed)
        #expect(weakResource == nil)
        ads = nil
        #expect(weakAds == nil)
    }

}
