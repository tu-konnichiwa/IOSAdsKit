# IOSAdsKit

Reusable ad orchestration for iOS with a pure Swift core and a Google Mobile Ads driver. It centralizes high-floor fallback, caching, load deadlines and full-screen lifecycle handling, keeping app policy outside the SDK.

## Features

- Interstitial, app-open and rewarded ads coordinated within one full-screen scope.
- Adaptive banner and native ad loading, with UIKit views and a SwiftUI integration example.
- **Optional high-floor ad ID plus required normal ad ID for every format.** High floor is attempted first; normal is loaded on failure or timeout. Equal IDs are requested once.
- Monotonic expiry, bounded per-floor timeouts, coalesced requests and stale callback protection.
- Format-scoped frequency limits, explicit host exclusions and app-open background eligibility.
- Earned-reward callback separate from presentation completion.
- Consent/subscription request gate, explicit cancellation/clear and typed errors.
- Deterministic core tests with injected SDK and clock ports.

## Requirements and installation

- iOS 15+, Swift 6 language mode; Xcode 26.2+ for the currently verified Google SDK; newer compatible SDK releases may raise toolchain requirements.
- The core also builds/tests on macOS 13+. The Google driver supports iOS only.
- Google Mobile Ads **13.4.0 or newer within 13.x** is supported by the dependency requirement (`13.4.0..<14.0.0`); UMP is its transitive dependency. The committed development resolution uses Google Mobile Ads 13.4.0 and UMP 3.1.0.

Add this repository/local folder through **Xcode → File → Add Package Dependencies**. Select `IOSAdsKitGoogleMobileAds` for the iOS integration and `IOSAdsKit` when directly using core types. In a local Swift package:

```swift
// dependencies
.package(path: "../IOSAdsKit")
// target dependencies
.product(name: "IOSAdsKit", package: "IOSAdsKit"),
.product(name: "IOSAdsKitGoogleMobileAds", package: "IOSAdsKit")
```

The repository has no published release/tag yet. A remote installation should use your actual repository URL after publishing; no placeholder remote dependency is required for local use.

Set `GADApplicationIdentifier` to your **AdMob app ID** in the host Info.plist, and maintain the SDK-required SKAdNetwork entries using [Google's setup guide](https://developers.google.com/admob/ios/quick-start). An app ID is different from an ad unit ID. The library does not modify Info.plist or initialize the SDK implicitly.

## Quick start

Run at your app's composition root on MainActor. Retain `ads` across the scene's lifetime and use a weak scene-owned presenter. Resolve consent and, when applicable, ATT through your app before starting the SDK. The presenter must be visible and active with no modal already presented.

```swift
import IOSAdsKit
import IOSAdsKitGoogleMobileAds

let ids = try AdUnitIDs(
    highFloorAdUnitID: "YOUR_HIGH_FLOOR_INTERSTITIAL_UNIT_ID", // omit with nil if unavailable
    normalAdUnitID: "YOUR_NORMAL_INTERSTITIAL_UNIT_ID"
)
let ads = GoogleAds(placements: [
    .common: try FullScreenAdConfiguration(
        format: .interstitial,
        adUnitIDs: ids,
        minimumInterval: 10
    )
], presenter: { [weak viewController] in viewController })

// After the host authorizes requests and resolves any required tracking flow:
await GoogleAds.start()
ads.setAdsEnabled(true)
ads.fullScreen.load(.common) { result in
    // Handle/report a load failure here; loadState(for:) also retains final failures.
}

// At a natural transition; preload well before this call.
ads.fullScreen.show(.common) { result in
    // Continue the host flow for dismissal, skip, and presentation failure alike.
}
```

For development use `GoogleTestAdUnitIDs` instead of live units. They correspond to [Google's official test units](https://developers.google.com/admob/ios/test-ads); the banner constant is for adaptive banners. To test two distinct floors, configure two test-enabled units. Supplying the same demo ID to both floors deduplicates into one normal request.

The [complete integration example](Examples/AdsIntegration.swift) includes all five formats, a UMP consent flow, privacy options, scene forwarding and a SwiftUI view wrapper. Copy it to your app and adapt host policy and view layout. Its demo IDs are for development.

## High floor and normal ID

The same configuration type serves every format:

```swift
let bannerIDs = try AdUnitIDs(
    highFloorAdUnitID: "YOUR_HIGH_FLOOR_BANNER_ID",
    normalAdUnitID: "YOUR_NORMAL_BANNER_ID"
)
let bannerConfig = try AdLoadConfiguration(adUnitIDs: bannerIDs, loadTimeout: 15)
let banner = try ads.makeBanner(configuration: bannerConfig, width: containerWidth)
// Retain banner and add banner.view to your hierarchy.
banner.load { result in
    // Success supplies the height in points; size the container to width × height.
}
// When this placement leaves the screen:
banner.clear()
```

High-floor IDs must point to ad units configured with your floor in AdMob. The library chooses the request order; it does not set eCPM floors or create ad units. Each ID must match its ad format. IDs are trimmed; empty IDs fail during configuration. A nil high-floor ID loads normal directly. High succeeds → stop. High fails/times out → normal. Normal fails/times out → final error. Cancellation does not advance to normal. There is no automatic endless retry.

## App-open and rewarded

```swift
let open = try FullScreenAdConfiguration(
    format: .appOpen,
    adUnitIDs: AdUnitIDs(highFloorAdUnitID: "YOUR_HIGH_OPEN_ID", normalAdUnitID: "YOUR_NORMAL_OPEN_ID"),
    minimumBackgroundDuration: 30,
    allowsColdStart: false
)
let rewarded = try FullScreenAdConfiguration(
    format: .rewarded,
    adUnitIDs: AdUnitIDs(highFloorAdUnitID: "YOUR_HIGH_REWARDED_ID", normalAdUnitID: "YOUR_NORMAL_REWARDED_ID")
)
// Include these in GoogleAds placements at construction.
// Forward your owning scene's background event:
ads.fullScreen.recordBackground()
// When foreground entry/loading UI is appropriate:
ads.fullScreen.show(.appOpen) { result in /* finish entry flow */ }

// On a user-requested rewarded action, with "unlock" configured:
ads.fullScreen.show("unlock", onReward: { reward in
    // Handle an earned reward here, at most once. Never award merely on dismissal.
}, completion: { result in
    // Finish/recover UI independently of whether a reward was earned.
})
```

App-open cache expires at four hours, including equality at that boundary, as required by [Google's app-open guidance](https://developers.google.com/admob/ios/app-open). The host forwards lifecycle events explicitly, avoiding global notification subscriptions and accidental presentations after entering content. Frequency limits use elapsed time from presentation, shared across placements of the same format. `bypassInterval` bypasses only that limit; `excluded: true` skips according to host policy. All full-screen formats share a presentation lock within the instance.

For security-sensitive rewards, use an authoritative backend. This initial driver does not expose server-side verification options; do not treat local earned events as authorization for protected value transfers.

## Native ads and list insertion

```swift
let nativeConfig = try AdLoadConfiguration(adUnitIDs: AdUnitIDs(
    highFloorAdUnitID: "YOUR_HIGH_NATIVE_ID", normalAdUnitID: "YOUR_NORMAL_NATIVE_ID"
))
let nativeLoader = ads.makeNativeLoader(configuration: nativeConfig)
// Retain nativeLoader while loading.
nativeLoader.load { result in
    switch result {
    case .success(let ad):
        // try ad.makeView() returns a registered UIView with attribution and assets.
        // Mount it in one hierarchy and supply container layout. A second makeView throws.
        break
    case .failure(let error):
        // Report the error and keep the content flow available.
        break
    }
}
```

Load one native ad per request. A parallel request to the same loader returns `.loadInProgress`, and each successful request transfers its ad out of cache. Keep distinct resources for distinct placements; do not reuse one ad in several list rows.

`AdList.inserting(ads, into: items, startAfter: 4, spacing: 4)` creates typed content/ad rows, retaining original content indices and each ad's index. `spacing` counts content items, rather than already inserted rows. It consumes every supplied ad at most once. Negative counts and zero spacing throw; empty content has no ad rows. `limit: nil` uses all supplied ads, and `limit: 0` inserts none.

## Configuration, errors and lifecycle

| Setting/API | Default / behavior |
|---|---|
| `highFloorAdUnitID` | nil; attempted first when provided and different from normal |
| `normalAdUnitID` | Required, nonempty |
| Full-screen `cacheLifetime` | 1 hour; 4 hours for app-open, which cannot exceed that limit |
| `loadTimeout` | 30 seconds **per floor**, finite, > 0 and ≤ 300 |
| `minimumInterval` | 10 seconds, shared by format across placements |
| `minimumBackgroundDuration` | 0 seconds; only applies to app-open |
| `allowsColdStart` | true; set false for warm-start-only app-open |
| `refreshPolicy` | `.afterPresentation`; `.manual` leaves reloading to the host |
| Requests enabled | false until `GoogleAds.setAdsEnabled(true)` |
| `clear(placement)` / loader `clear()` | Cancels logical loading and cache; visible full-screen ad continues |

All constructors and callbacks that manage resources use MainActor. Pure domain configuration is Sendable. Durations are seconds; banner sizes are points. Concurrent generic loads coalesce and their callbacks fire once. Do not block MainActor or wait synchronously for an SDK callback. Retain the client/controllers until their operations finish; clear loads on teardown. The SDK's underlying network work may continue after cancellation, but late results are ignored.

`AdsError` provides configuration, load, presentation, timeout, cancellation, disabled and in-progress failures. SDK failures include a normalized diagnostic message, while their concrete exception types remain in the driver. The shared driver mapper preserves request cancellation and platform network timeout as typed outcomes. `AdShowResult` distinguishes dismissal, typed skip reasons and presentation failures. A missing ready ad skips immediately and starts loading for the next opportunity. For preloads that omit a completion, inspect `loadState(for:)` to report final errors. A high-floor error recovered by normal is a successful waterfall.

When consent/subscription changes, call **GoogleAds.setAdsEnabled**. It clears banner/native pending work and full-screen caches. It cannot remove native views already delivered to the host; remove those explicitly. Disabling cannot dismiss SDK full-screen content already visible. Directly calling `ads.fullScreen.setAdsEnabled` controls only the full-screen core; use the facade for the integrated scope.

## Testing and validation

```sh
swift test
xcodebuild -scheme IOSAdsKitGoogleMobileAds \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme IOSAdsKitGoogleMobileAds \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Select the installed Xcode through `DEVELOPER_DIR` if command line tools are your default. Initial SPM resolution downloads official binary dependencies; tests use injected loaders and virtual monotonic time with no network, real database or simulator. Tests cover both floors, final failure/retry, timeout, cancellation, late/duplicate callbacks, cache boundaries, exclusions, format-wide frequency, cross-format presentation locking, app-open lifecycle, reward deduplication and reentrancy. CI builds device/simulator variants and runs core tests. See [verification and release gaps](Docs/Quality.md) for actual results and remaining device verification.

## Limits and compatibility

- iOS driver support only; macOS is a host for the pure core/test suite.
- Consent, ATT, subscription checks, remote config and scene navigation belong to the host. UMP integration is an example, not an automatic library side effect.
- Native rendering has one standard layout. The host controls its frame and can present its view in a custom screen. There is no native batch cache or built-in full-screen native scene.
- Banner width is fixed per controller; clear and recreate after width/orientation layout changes. Render the banner using its returned height. SDK-managed visible refresh is separate from the waterfall's initial high/normal selection.
- No impression/revenue stream, custom request targeting, mediation network configuration or server-side reward verification API in this version.
- The SDK dependency accepts `13.4.0..<14.0.0`, allowing apps to resolve compatible 13.x updates. Current verification covers 13.4.0; validate later versions before releasing your app.
- Package build verifies compilation, not successful delivery, revenue or mediation in an installed app.

Initial API version: **0.1.0 (unreleased)**. Semantic versioning is the intended policy: 0.x minors may change APIs with migration notes; after 1.0, incompatible changes require a major version and documented migration. Future deprecations should include a replacement and migration window. No compatibility with unrelated SDK wrappers is implied.

See [architecture rationale](Docs/Architecture.md), [public API reference](Docs/API.md), [release gaps](Docs/Quality.md), and [changelog](CHANGELOG.md).
