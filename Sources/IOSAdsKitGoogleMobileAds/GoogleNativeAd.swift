#if os(iOS)
import GoogleMobileAds
import IOSAdsKit
import UIKit

/// One native ad. Keep its view in a single hierarchy; repeated makeView calls fail.
/// The view retains the SDK resource. Host UI owns visibility and removal after consent changes.
@MainActor
public final class GoogleNativeAd {
    private let ad: NativeAd
    private var rendered = false
    init(_ ad: NativeAd) { self.ad = ad }

    /// Creates a standard asset-registered view with ad attribution, media and CTA.
    /// SDK types stay inside the driver; caller controls container layout and height.
    public func makeView() throws -> UIView {
        guard !rendered else { throw AdsError.invalidConfiguration("A native ad can only be rendered once") }
        rendered = true
        return NativeAdRenderer.makeView(ad: ad)
    }
}

/// Loads one native ad per request, trying high floor before normal. A parallel call
/// is rejected instead of handing the same SDK resource to multiple callers.
@MainActor
public final class GoogleNativeAdLoader {
    private let waterfall: AdWaterfall<GoogleNativeAd>
    private let enabled: @MainActor () -> Bool
    private var loading = false
    public var state: AdLoadState { waterfall.state }

    init(
        configuration: AdLoadConfiguration, scheduler: any AdScheduler,
        presenter: @escaping @MainActor () -> UIViewController?, enabled: @escaping @MainActor () -> Bool
    ) {
        self.enabled = enabled
        waterfall = AdWaterfall(configuration: configuration, scheduler: scheduler) { id, completion in
            let request = NativeRequest(id: id, presenter: presenter(), completion: completion)
            request.start()
            return DriverCancellation { request.cancel() }
        }
    }

    public func load(completion: @escaping @MainActor (Result<GoogleNativeAd, AdsError>) -> Void) {
        guard enabled() else { completion(.failure(.adsDisabled)); return }
        guard !loading else { completion(.failure(.loadInProgress)); return }
        loading = true
        waterfall.load { [weak self] result in
            guard let self else { completion(.failure(.cancelled)); return }
            self.loading = false
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let ad):
                _ = self.waterfall.takeReadyAd()
                guard self.enabled() else { completion(.failure(.adsDisabled)); return }
                completion(.success(ad))
            }
        }
    }

    /// Cancel pending work. Already delivered ads belong to the host.
    public func clear() { waterfall.invalidate() }
}

@MainActor
private final class NativeRequest: NSObject, NativeAdLoaderDelegate {
    private let loader: AdLoader
    private let hasPresenter: Bool
    private var completion: (@MainActor (Result<GoogleNativeAd, AdsError>) -> Void)?

    init(id: String, presenter: UIViewController?, completion: @escaping @MainActor (Result<GoogleNativeAd, AdsError>) -> Void) {
        hasPresenter = presenter != nil
        loader = AdLoader(adUnitID: id, rootViewController: presenter, adTypes: [.native], options: nil)
        self.completion = completion
        super.init()
        loader.delegate = self
    }
    func start() {
        guard hasPresenter else {
            finish(.failure(.loadFailed(message: "Native ad requires a root view controller"))); return
        }
        loader.load(Request())
    }
    func cancel() { completion = nil; loader.delegate = nil }
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) { finish(.success(GoogleNativeAd(nativeAd))) }
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        finish(.failure(GoogleAdErrorMapper.loading(error)))
    }
    private func finish(_ result: Result<GoogleNativeAd, AdsError>) {
        let callback = completion
        cancel()
        callback?(result)
    }
}

/// Pure asset-to-view binding belongs at the framework edge. NativeAdView performs click
/// registration and adds the AdChoices overlay; the attribution label stays visible.
@MainActor
private enum NativeAdRenderer {
    static func makeView(ad: NativeAd) -> UIView {
        let view = NativeAdView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12
        let attribution = UILabel()
        attribution.text = "Ad"
        attribution.font = .systemFont(ofSize: 11, weight: .semibold)
        attribution.textColor = .secondaryLabel
        let headline = UILabel()
        headline.text = ad.headline
        headline.font = .preferredFont(forTextStyle: .headline)
        headline.numberOfLines = 2
        let body = UILabel()
        body.text = ad.body
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.numberOfLines = 3
        let advertiser = UILabel()
        advertiser.text = ad.advertiser
        advertiser.font = .preferredFont(forTextStyle: .caption1)
        let media = MediaView()
        media.mediaContent = ad.mediaContent
        let callToAction = UIButton(type: .system)
        callToAction.setTitle(ad.callToAction, for: .normal)
        callToAction.isUserInteractionEnabled = false // SDK owns tap handling.
        let icon = UIImageView(image: ad.icon?.image)
        icon.contentMode = .scaleAspectFit
        let titleRow = UIStackView(arrangedSubviews: [icon, headline])
        titleRow.spacing = 8
        let stack = UIStackView(arrangedSubviews: [attribution, titleRow, advertiser, media, body, callToAction])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            media.heightAnchor.constraint(equalToConstant: 180),
            callToAction.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        view.headlineView = headline
        view.bodyView = body
        view.advertiserView = advertiser
        view.iconView = icon
        view.mediaView = media
        view.callToActionView = callToAction
        view.nativeAd = ad
        return view
    }
}
#endif
