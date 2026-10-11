#if os(iOS)
import GoogleMobileAds
import IOSAdsKit
import UIKit

/// Owns one adaptive banner and its load lifecycle. Add view to the host's hierarchy,
/// retain this controller, call load, and clear when the placement leaves the screen.
@MainActor
public final class GoogleBannerAd {
    public let view = UIView()
    public let width: CGFloat
    private let waterfall: AdWaterfall<BannerView>
    private let enabled: @MainActor () -> Bool
    private var generation: UInt64 = 0
    public var state: AdLoadState { waterfall.state }

    init(
        configuration: AdLoadConfiguration, width: CGFloat, size: AdSize, scheduler: any AdScheduler,
        presenter: @escaping @MainActor () -> UIViewController?, enabled: @escaping @MainActor () -> Bool
    ) {
        self.width = width
        self.enabled = enabled
        self.waterfall = AdWaterfall(configuration: configuration, scheduler: scheduler) { id, completion in
            let request = BannerRequest(id: id, size: size, presenter: presenter(), completion: completion)
            request.start()
            return DriverCancellation { request.cancel() }
        }
    }

    /// Success installs the banner and reports its natural height in points.
    /// Every coalesced caller completes once. Read errors instead of inferring them from view visibility.
    public func load(completion: @escaping @MainActor (Result<CGFloat, AdsError>) -> Void = { _ in }) {
        guard enabled() else { completion(.failure(.adsDisabled)); return }
        let current = generation
        waterfall.load { [weak self] result in
            guard let self else { completion(.failure(.cancelled)); return }
            guard self.generation == current else { completion(.failure(.cancelled)); return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let banner):
                guard self.enabled() else { completion(.failure(.adsDisabled)); return }
                self.view.subviews.forEach { $0.removeFromSuperview() }
                banner.translatesAutoresizingMaskIntoConstraints = false
                self.view.addSubview(banner)
                NSLayoutConstraint.activate([
                    banner.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                    banner.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
                ])
                completion(.success(cgSize(for: banner.adSize).height))
            }
        }
    }

    /// Stops rendering/refresh and completes pending loads with cancellation.
    public func clear() {
        generation &+= 1
        view.subviews.forEach { $0.removeFromSuperview() }
        waterfall.invalidate()
    }
}

@MainActor
private final class BannerRequest: NSObject, BannerViewDelegate {
    private let banner: BannerView
    private var completion: (@MainActor (Result<BannerView, AdsError>) -> Void)?

    init(
        id: String, size: AdSize, presenter: UIViewController?,
        completion: @escaping @MainActor (Result<BannerView, AdsError>) -> Void
    ) {
        banner = BannerView(adSize: size)
        banner.adUnitID = id
        banner.rootViewController = presenter
        self.completion = completion
        super.init()
        banner.delegate = self
    }

    func start() {
        guard banner.rootViewController != nil else {
            finish(.failure(.loadFailed(message: "Banner requires a root view controller"))); return
        }
        banner.load(Request())
    }
    func cancel() { completion = nil; banner.delegate = nil }
    func bannerViewDidReceiveAd(_ bannerView: BannerView) { finish(.success(bannerView)) }
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
        finish(.failure(GoogleAdErrorMapper.loading(error)))
    }
    private func finish(_ result: Result<BannerView, AdsError>) {
        let callback = completion
        cancel()
        callback?(result)
    }
}
#endif
