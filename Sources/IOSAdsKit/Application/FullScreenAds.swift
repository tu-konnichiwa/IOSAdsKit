public enum AdSkipReason: Equatable, Sendable {
    case adsDisabled, unknownPlacement, notReady, alreadyPresenting, frequencyCapped
    case backgroundTooShort, coldStartDisabled, excluded
}

public enum AdShowResult: Equatable, Sendable {
    case dismissed
    case skipped(AdSkipReason)
    case failed(AdsError)
}

/// Own one instance per app/scene ad scope. It coordinates all full-screen formats,
/// so interstitial, rewarded and app-open cannot overlap within that scope.
/// No UI discovery, SDK initialization or consent prompting occurs here.
@MainActor
public final class FullScreenAds {
    private struct PlacementEntry {
        let configuration: FullScreenAdConfiguration
        let waterfall: AdWaterfall<any FullScreenAd>
    }
    private struct Presentation {
        let id: UInt64
        let placement: AdPlacement
        let ad: any FullScreenAd
        let completion: @MainActor (AdShowResult) -> Void
        let onReward: @MainActor (AdReward) -> Void
        var didPresent = false
        var didReward = false
    }

    private let entries: [AdPlacement: PlacementEntry]
    private let scheduler: any AdScheduler
    private var presentation: Presentation?
    private var presentationID: UInt64 = 0
    private var lastShownAt: [FullScreenAdFormat: Double] = [:]
    private var backgroundedAt: Double?
    public private(set) var adsEnabled: Bool
    public var isPresenting: Bool { presentation != nil }

    /// Disabled by default: enable only after the host has resolved consent and SDK startup.
    public init(
        placements: [AdPlacement: FullScreenAdConfiguration],
        loader: any FullScreenAdLoading,
        scheduler: any AdScheduler,
        adsEnabled: Bool = false
    ) {
        self.scheduler = scheduler
        self.adsEnabled = adsEnabled
        self.entries = placements.mapValues { configuration in
            PlacementEntry(configuration: configuration, waterfall: AdWaterfall(
                configuration: configuration.load, scheduler: scheduler
            ) { id, completion in
                loader.load(format: configuration.format, adUnitID: id, completion: completion)
            })
        }
    }

    /// Disabling cancels loads and discards caches. An already visible ad finishes normally.
    public func setAdsEnabled(_ enabled: Bool) {
        adsEnabled = enabled
        if !enabled { entries.values.forEach { $0.waterfall.invalidate() } }
    }

    public func loadState(for placement: AdPlacement) -> AdLoadState? { entries[placement]?.waterfall.state }
    public func isAvailable(_ placement: AdPlacement) -> Bool {
        adsEnabled && entries[placement]?.waterfall.isReady == true
    }

    /// Coalesces in-flight loads and preserves a valid cached ad.
    public func load(_ placement: AdPlacement, completion: @escaping @MainActor (Result<Void, AdsError>) -> Void = { _ in }) {
        guard adsEnabled else { completion(.failure(.adsDisabled)); return }
        guard let entry = entries[placement] else {
            completion(.failure(.invalidConfiguration("Unknown placement: \(placement.rawValue)"))); return
        }
        entry.waterfall.load { completion($0.map { _ in () }) }
    }

    public func preloadAll() {
        for placement in entries.keys { load(placement) }
    }

    /// Cancels all callers waiting on this placement. Does not dismiss a visible ad.
    public func clear(_ placement: AdPlacement) { entries[placement]?.waterfall.invalidate() }

    /// Forward the owning scene's didEnterBackground event. Ad-click transitions are ignored.
    public func recordBackground() {
        guard presentation == nil else { return }
        backgroundedAt = scheduler.now
    }

    /// Presents only a cached ad, otherwise skips immediately and starts loading for next time.
    /// Completion fires once on MainActor. Reward fires at most once, on earnedReward.
    /// Frequency is shared across placements of the same format, measured from presentation.
    /// Exclusion is supplied by the host's policy; bypassInterval bypasses only frequency.
    public func show(
        _ placement: AdPlacement,
        excluded: Bool = false,
        bypassInterval: Bool = false,
        onReward: @escaping @MainActor (AdReward) -> Void = { _ in },
        completion: @escaping @MainActor (AdShowResult) -> Void
    ) {
        if !adsEnabled { completion(.skipped(.adsDisabled)); return }
        if excluded { completion(.skipped(.excluded)); return }
        guard let entry = entries[placement] else { completion(.skipped(.unknownPlacement)); return }
        guard presentation == nil else { completion(.skipped(.alreadyPresenting)); return }
        let configuration = entry.configuration
        if !bypassInterval, let last = lastShownAt[configuration.format],
           scheduler.now - last < configuration.minimumInterval {
            completion(.skipped(.frequencyCapped)); return
        }
        if configuration.format == .appOpen {
            if let backgroundedAt {
                if scheduler.now - backgroundedAt < configuration.minimumBackgroundDuration {
                    completion(.skipped(.backgroundTooShort)); return
                }
            } else if !configuration.allowsColdStart {
                completion(.skipped(.coldStartDisabled)); return
            }
        }
        guard let ad = entry.waterfall.takeReadyAd() else {
            load(placement)
            completion(.skipped(.notReady)); return
        }
        presentationID &+= 1
        let id = presentationID
        presentation = Presentation(id: id, placement: placement, ad: ad, completion: completion, onReward: onReward)
        ad.present { [weak self] event in self?.receive(event, id: id) }
    }

    private func receive(_ event: FullScreenAdEvent, id: UInt64) {
        guard var active = presentation, active.id == id, let entry = entries[active.placement] else { return }
        switch event {
        case .presented:
            guard !active.didPresent else { return }
            active.didPresent = true
            presentation = active
            lastShownAt[entry.configuration.format] = scheduler.now
        case .earnedReward(let reward):
            guard entry.configuration.format == .rewarded, !active.didReward else { return }
            active.didReward = true
            presentation = active
            active.onReward(reward)
        case .dismissed:
            finish(active, entry: entry, result: .dismissed)
        case .failed(let error):
            finish(active, entry: entry, result: .failed(error))
        }
    }

    private func finish(_ active: Presentation, entry: PlacementEntry, result: AdShowResult) {
        presentation = nil
        if entry.configuration.format == .appOpen { backgroundedAt = nil }
        // Reload before the callback: reentrant callers see a consistent new load state.
        if adsEnabled, entry.configuration.refreshPolicy == .afterPresentation { load(active.placement) }
        active.completion(result)
    }
}
