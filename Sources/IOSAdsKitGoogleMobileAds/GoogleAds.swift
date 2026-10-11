#if os(iOS)
import GoogleMobileAds
import IOSAdsKit
import UIKit

/// Composition root. Retain one instance per scene and supply its visible presenter.
/// It never searches global windows or implicitly starts the SDK.
@MainActor
public final class GoogleAds {
    public let fullScreen: FullScreenAds
    private let scheduler: any AdScheduler
    private let presenter: @MainActor () -> UIViewController?
    private var banners: [WeakBanner] = []
    private var nativeLoaders: [WeakNativeLoader] = []

    public init(
        placements: [AdPlacement: FullScreenAdConfiguration],
        presenter: @escaping @MainActor () -> UIViewController?
    ) {
        let scheduler = SystemAdScheduler()
        self.scheduler = scheduler
        self.presenter = presenter
        self.fullScreen = FullScreenAds(
            placements: placements, loader: GoogleFullScreenLoader(presenter: presenter), scheduler: scheduler
        )
    }

    /// Call after resolving host consent/tracking requirements and before enabling requests.
    /// Requires GADApplicationIdentifier and the SDK's required Info.plist configuration.
    public static func start() async { _ = await MobileAds.shared.start() }

    /// Apply host consent/subscription policy to every resource created by this instance.
    /// Existing full-screen content is allowed to finish. Banner/native caches are cleared.
    public func setAdsEnabled(_ enabled: Bool) {
        fullScreen.setAdsEnabled(enabled)
        banners = banners.filter { $0.value != nil }
        nativeLoaders = nativeLoaders.filter { $0.value != nil }
        if !enabled {
            banners.forEach { $0.value?.clear() }
            nativeLoaders.forEach { $0.value?.clear() }
        }
    }

    /// Width is in points and must be finite and positive. Use the owning container's width.
    /// A size change needs a new banner controller; Google manages refresh while visible.
    public func makeBanner(configuration: AdLoadConfiguration, width: CGFloat) throws -> GoogleBannerAd {
        guard width.isFinite, width > 0 else { throw AdsError.invalidConfiguration("Banner width must be positive") }
        let size = largeAnchoredAdaptiveBanner(width: width)
        guard isAdSizeValid(size: size) else {
            throw AdsError.invalidConfiguration("SDK does not support this adaptive banner width")
        }
        let banner = GoogleBannerAd(
            configuration: configuration, width: width, size: size, scheduler: scheduler, presenter: presenter,
            enabled: { [weak self] in self?.fullScreen.adsEnabled == true }
        )
        banners = banners.filter { $0.value != nil }
        banners.append(WeakBanner(value: banner))
        return banner
    }

    /// Retain the loader while loading; consume each returned native ad in one view only.
    public func makeNativeLoader(configuration: AdLoadConfiguration) -> GoogleNativeAdLoader {
        let loader = GoogleNativeAdLoader(
            configuration: configuration, scheduler: scheduler, presenter: presenter,
            enabled: { [weak self] in self?.fullScreen.adsEnabled == true }
        )
        nativeLoaders = nativeLoaders.filter { $0.value != nil }
        nativeLoaders.append(WeakNativeLoader(value: loader))
        return loader
    }
}

private struct WeakBanner { weak var value: GoogleBannerAd? }
private struct WeakNativeLoader { weak var value: GoogleNativeAdLoader? }
#endif
