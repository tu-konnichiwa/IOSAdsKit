#if os(iOS)
import GoogleMobileAds
import IOSAdsKit
import UIKit

@MainActor
final class DriverCancellation: AdCancellation {
    private var action: (@MainActor () -> Void)?
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    func cancel() { let action = action; self.action = nil; action?() }
    deinit {
        if let action { Task { @MainActor in action() } }
    }
}

@MainActor
final class GoogleFullScreenLoader: FullScreenAdLoading {
    private let presenter: @MainActor () -> UIViewController?
    init(presenter: @escaping @MainActor () -> UIViewController?) { self.presenter = presenter }

    func load(
        format: FullScreenAdFormat,
        adUnitID: String,
        completion: @escaping @MainActor (Result<any FullScreenAd, AdsError>) -> Void
    ) -> any AdCancellation {
        let task = Task { @MainActor [presenter] in
            do {
                let resource: GoogleFullScreenResource
                switch format {
                case .interstitial:
                    resource = .interstitial(try await InterstitialAd.load(with: adUnitID, request: Request()))
                case .appOpen:
                    resource = .appOpen(try await AppOpenAd.load(with: adUnitID, request: Request()))
                case .rewarded:
                    resource = .rewarded(try await RewardedAd.load(with: adUnitID, request: Request()))
                }
                guard !Task.isCancelled else { return }
                completion(.success(GoogleFullScreenAd(resource: resource, presenter: presenter)))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(GoogleAdErrorMapper.loading(error)))
            }
        }
        return DriverCancellation { task.cancel() }
    }
}

private enum GoogleFullScreenResource {
    case interstitial(InterstitialAd)
    case appOpen(AppOpenAd)
    case rewarded(RewardedAd)
}

@MainActor
private final class GoogleFullScreenAd: NSObject, FullScreenAd, FullScreenContentDelegate {
    private let resource: GoogleFullScreenResource
    private let presenter: @MainActor () -> UIViewController?
    private var onEvent: (@MainActor (FullScreenAdEvent) -> Void)?
    private var consumed = false

    init(resource: GoogleFullScreenResource, presenter: @escaping @MainActor () -> UIViewController?) {
        self.resource = resource
        self.presenter = presenter
    }

    func present(onEvent: @escaping @MainActor (FullScreenAdEvent) -> Void) {
        guard !consumed else {
            onEvent(.failed(.presentationFailed(message: "Ad was already consumed"))); return
        }
        consumed = true
        self.onEvent = onEvent
        guard let controller = presenter(), controller.viewIfLoaded?.window != nil,
              controller.presentedViewController == nil,
              !controller.isBeingDismissed, !controller.isBeingPresented,
              UIApplication.shared.applicationState == .active else {
            finish(.failed(.presentationFailed(message: "Presenter must be visible, active and free of a presented controller")))
            return
        }
        do {
            switch resource {
            case .interstitial(let ad):
                try ad.canPresent(from: controller)
                ad.fullScreenContentDelegate = self
                ad.present(from: controller)
            case .appOpen(let ad):
                try ad.canPresent(from: controller)
                ad.fullScreenContentDelegate = self
                ad.present(from: controller)
            case .rewarded(let ad):
                try ad.canPresent(from: controller)
                ad.fullScreenContentDelegate = self
                ad.present(from: controller) { [weak self, weak ad] in
                    guard let ad else { return }
                    self?.onEvent?(.earnedReward(AdReward(amount: ad.adReward.amount.doubleValue, type: ad.adReward.type)))
                }
            }
        } catch { finish(.failed(GoogleAdErrorMapper.presentation(error))) }
    }

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) { onEvent?(.presented) }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) { finish(.dismissed) }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        finish(.failed(GoogleAdErrorMapper.presentation(error)))
    }

    private func finish(_ event: FullScreenAdEvent) {
        let callback = onEvent
        onEvent = nil
        switch resource {
        case .interstitial(let ad): ad.fullScreenContentDelegate = nil
        case .appOpen(let ad): ad.fullScreenContentDelegate = nil
        case .rewarded(let ad): ad.fullScreenContentDelegate = nil
        }
        callback?(event)
    }
}
#endif
