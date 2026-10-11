import IOSAdsKit
import IOSAdsKitGoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

/// App composition example. Replace demo units with your own high/normal pairs at release.
/// Retain this object at the app/scene composition root, rather than creating it per tap.
@MainActor
final class AdsIntegration {
    let ads: GoogleAds
    private(set) var banner: GoogleBannerAd?
    private(set) var nativeLoader: GoogleNativeAdLoader?

    init(presenter: @escaping @MainActor () -> UIViewController?) throws {
        let interstitialIDs = try AdUnitIDs(normalAdUnitID: GoogleTestAdUnitIDs.interstitial)
        let appOpenIDs = try AdUnitIDs(normalAdUnitID: GoogleTestAdUnitIDs.appOpen)
        let rewardedIDs = try AdUnitIDs(normalAdUnitID: GoogleTestAdUnitIDs.rewarded)
        ads = GoogleAds(placements: [
            .splash: try FullScreenAdConfiguration(
                format: .interstitial, adUnitIDs: interstitialIDs, refreshPolicy: .manual
            ),
            .common: try FullScreenAdConfiguration(format: .interstitial, adUnitIDs: interstitialIDs),
            .appOpen: try FullScreenAdConfiguration(
                format: .appOpen, adUnitIDs: appOpenIDs, minimumBackgroundDuration: 30, allowsColdStart: false
            ),
            "unlock": try FullScreenAdConfiguration(format: .rewarded, adUnitIDs: rewardedIDs)
        ], presenter: presenter)
    }

    /// Call from a visible, active presenter. Your app owns ATT if tracking is requested.
    /// Update consent information each session; a previous valid consent may survive an update error.
    func prepare(from controller: UIViewController, isSubscribed: Bool,
                 reportConsentError: @MainActor (any Error) -> Void) async {
        ads.setAdsEnabled(false)
        let parameters = RequestParameters()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: controller)
        } catch { reportConsentError(error) }
        guard !Task.isCancelled, ConsentInformation.shared.canRequestAds, !isSubscribed else { return }
        await GoogleAds.start()
        guard !Task.isCancelled else { return }
        ads.setAdsEnabled(true)
        ads.fullScreen.preloadAll()
    }

    /// Invoke in response to the user's privacy-options action, then apply the new policy.
    func privacyOptions(from controller: UIViewController, isSubscribed: Bool) async throws {
        ads.setAdsEnabled(false)
        defer { ads.setAdsEnabled(ConsentInformation.shared.canRequestAds && !isSubscribed) }
        try await ConsentForm.presentPrivacyOptionsForm(from: controller)
    }

    func makeBanner(width: CGFloat, completion: @escaping @MainActor (Result<CGFloat, AdsError>) -> Void) throws -> UIView {
        banner?.clear()
        let configuration = try AdLoadConfiguration(adUnitIDs: AdUnitIDs(normalAdUnitID: GoogleTestAdUnitIDs.banner))
        let banner = try ads.makeBanner(configuration: configuration, width: width)
        self.banner = banner
        banner.load(completion: completion)
        return banner.view
    }

    func loadNative(completion: @escaping @MainActor (Result<GoogleNativeAd, AdsError>) -> Void) throws {
        let configuration = try AdLoadConfiguration(adUnitIDs: AdUnitIDs(normalAdUnitID: GoogleTestAdUnitIDs.native))
        if nativeLoader == nil { nativeLoader = ads.makeNativeLoader(configuration: configuration) }
        nativeLoader?.load(completion: completion)
    }

    func didEnterBackground() { ads.fullScreen.recordBackground() }

    func didBecomeActive(completion: @escaping @MainActor (AdShowResult) -> Void) {
        // The host should call only while the loading/entry UI is suitable for an ad.
        ads.fullScreen.show(.appOpen, completion: completion)
    }

    func advance(completion: @escaping @MainActor (AdShowResult) -> Void) {
        ads.fullScreen.show(.common, completion: completion)
    }

    func unlock(onReward: @escaping @MainActor (AdReward) -> Void,
                completion: @escaping @MainActor (AdShowResult) -> Void) {
        ads.fullScreen.show("unlock", onReward: onReward, completion: completion)
    }
}

/// Wrap a retained banner/native view. The host controls its frame, state, and teardown.
@MainActor
struct AdUIView: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
