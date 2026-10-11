# Public API reference

## Core product: IOSAdsKit

Core policy types are independent of UIKit and Google Mobile Ads. Configuration/value types are Sendable. Resource controllers and ports are MainActor-isolated; callbacks run on MainActor and can be called synchronously when a cached result or skip is available.

| Type | Contract |
|---|---|
| `AdUnitIDs` | Throwing initializer accepts optional `highFloorAdUnitID` and required `normalAdUnitID`. Trims surrounding whitespace, rejects empty supplied IDs, deduplicates equal IDs. `attempts` returns the ordered `(floor, adUnitID)` pairs. |
| `AdFloor` | `.high` / `.normal`, identifying request order and ready resource provenance. |
| `AdPlacement` | Hashable, Sendable host-owned string identifier, also expressible by string literal. `rawValue` exposes the identifier. `.splash`, `.common`, `.appOpen` are conveniences; arbitrary identifiers are supported. |
| `FullScreenAdFormat` | `.interstitial`, `.appOpen`, `.rewarded`. The format chooses SDK loading and frequency scope. |
| `AdLoadConfiguration` | Immutable IDs, cache lifetime and per-attempt load timeout. Durations are finite positive seconds; timeout cannot exceed 300. Defaults: TTL 3,600 seconds, timeout 30 seconds. |
| `FullScreenAdConfiguration` | Immutable format, load configuration, refresh, interval, background and cold-start policies. Nonnegative finite minimum durations. TTL default 3,600 seconds, or 14,400 for app-open; app-open TTL cannot exceed 14,400. |
| `AdRefreshPolicy` | `.afterPresentation` reloads after dismissal or failed presentation; `.manual` requires a host load. Final load failures never trigger an endless retry. |
| `AdReward` | Immutable SDK-mapped amount and type. An earned event is separate from dismissal. Local events are not authoritative authorization for protected backend changes. |
| `AdsError` | `.invalidConfiguration(String)`, `.loadFailed(message:)`, `.presentationFailed(message:)`, `.timedOut`, `.cancelled`, `.adsDisabled`, `.loadInProgress`. Driver errors expose normalized nonempty diagnostic strings rather than vendor types. Request cancellation maps to cancelled; platform network timeouts map to timedOut. |
| `AdLoadState` | `.idle`, `.loading(AdFloor)`, `.ready(AdFloor)`, `.failed(AdsError)`. Cache expiry changes ready to idle. |
| `AdSkipReason` | `.adsDisabled`, `.unknownPlacement`, `.notReady`, `.alreadyPresenting`, `.frequencyCapped`, `.backgroundTooShort`, `.coldStartDisabled`, `.excluded`. Skips are normal admission outcomes. |
| `AdShowResult` | `.dismissed`, `.skipped(AdSkipReason)`, `.failed(AdsError)`. Successful dismissal does not itself imply an earned reward. |

### FullScreenAds

`init(placements:loader:scheduler:adsEnabled:)` injects platform loading and time. The default request gate is disabled. Retain the instance until presentations finish. One instance coordinates every full-screen format in its scope; use the same instance for placements that must not overlap.

| Member | Behavior and ownership |
|---|---|
| `adsEnabled` | Read-only request/admission gate. |
| `isPresenting` | True from reservation through terminal SDK dismissal/failure; includes the presentation transition. |
| `setAdsEnabled(_:)` | Disabling invalidates pending loads and cached resources. A visible ad finishes normally; its reward/completion can still fire. |
| `loadState(for:)` | Returns nil for an unknown placement, otherwise its current cache/load state; reading discards expired cache. |
| `isAvailable(_:)` | True only if enabled and a nonexpired ad is cached for this placement. |
| `load(_:completion:)` | Cached success or coalesced bounded loading; completion is `Result<Void, AdsError>`. Unknown placement yields invalidConfiguration, disabled yields adsDisabled. Without a callback, inspect loadState for errors. |
| `preloadAll()` | Starts a load for each configured placement. Does nothing externally while disabled; each state retains its outcome. |
| `clear(_:)` | Invalidates a placement's cache and pending loads. Unknown is a no-op; it does not dismiss or lose the completion of a visible ad. |
| `recordBackground()` | Records monotonic time from the owning scene's event, unless an ad is reserved/presenting. No global observers are installed. |
| `show(_:excluded:bypassInterval:onReward:completion:)` | Admits only a ready ad. Missing cache starts loading and immediately skips. Exclusion is host policy. Only frequency can be bypassed. Callback fires once on terminal event or synchronous skip, reward at most once only for rewarded. Auto refresh begins before terminal completion. |

Frequency time starts at the first presented event and is shared across placements of the same format. Each requested placement supplies the minimum interval for admission. App-open background duration is checked against the latest background event. An app-open terminal event clears that timestamp; `allowsColdStart` determines eligibility with no timestamp. Host UI must call show only at a suitable entry/loading opportunity.

### AdWaterfall<Resource>

A MainActor cache/load controller shared by SDK drivers and custom integrations. `init(configuration:scheduler:loader:)` receives a loader closure `(String, completion) -> AdCancellation`. Hold the waterfall until requests finish. The loader must eventually succeed/fail; timeouts bound missing callbacks. It can complete inline, but must not leak external error types.

- `state` discards expired cache and exposes the stable state contract.
- `isReady` checks current nonexpired cache.
- `load(completion:)` returns cached resources or joins one load. High is attempted before normal; errors/timeouts fall back once. Each pending caller completes once, even when invalidated. Coalesced successes share the same resource; single-use consumers must enforce ownership at their boundary.
- `takeReadyAd()` transfers the resource out of cache, returning nil when unavailable. Subsequent calls return nil until another successful load.
- `invalidate()` cancels pending work, clears cache and completes callers with cancelled. Driver network work can continue; its callbacks are ignored. Callback reentrancy cannot revive the invalidated attempt.

### Driver ports and clock

- `AdCancellation.cancel()` is idempotent and removes logical interest in a request. It must not subsequently report successful completion.
- `AdScheduler.now` supplies monotonic seconds. `schedule(after:_:)` must enqueue a MainActor deadline, never run inline, and return cancellable work.
- `SystemAdScheduler` is the included Foundation/Task clock driver. Public deadlines require a finite duration in [0, 300] seconds. Cancellation/deallocation removes its deadline.
- `FullScreenAdLoading.load(format:adUnitID:completion:)` returns an AdCancellation and delivers a typed SDK-independent resource/error. It must keep the resource driver alive until completion.
- `FullScreenAd.present(onEvent:)` is one-use and platform-context-free at the core boundary. The driver retains its actual presenter. Events are `.presented`, `.earnedReward(AdReward)`, `.dismissed`, `.failed(AdsError)`. Finish with dismissed/failed so the presentation reservation can release.

### AdList

`AdList.inserting(_:into:startAfter:spacing:limit:)` returns typed `AdListItem<Content, Ad>` rows. `startAfter` defaults to 4, spacing to 4, limit to nil. Start and limit must be nonnegative, spacing positive; invalid values throw invalidConfiguration. Each supplied ad is used at most once. An empty content list returns empty. Start counts original content items, and spacing counts content between ad rows. Zero start inserts before the first content item. Rows are `.content(value, originalIndex:)` and `.ad(value, adIndex:)`; indices refer to the original inputs. The generic row supports conditional Equatable and Sendable conformance.

## iOS driver product: IOSAdsKitGoogleMobileAds

All resource APIs are MainActor-isolated. The driver imports SDK/UIKit; those types do not cross into core policy. The host receives UIKit views, not SDK resources.

### GoogleAds

`init(placements:presenter:)` is the composition root; no implicit startup or global window traversal occurs. A scene-owned presenter closure returns the current visible UIViewController or nil. Capture owners weakly to avoid retain cycles.

- `fullScreen` exposes the configured FullScreenAds instance. Use its load/show/recordBackground methods.
- Static `start()` awaits Google SDK startup. Call after host consent/tracking policy and before enabling requests; configure the app's Info.plist first.
- `setAdsEnabled(_:)` applies to the integrated resource scope. Disabling clears full-screen caches, live banner views and native pending work. Already delivered native views belong to the host and must be removed explicitly.
- `makeBanner(configuration:width:)` validates finite positive point width and returns a GoogleBannerAd. The host retains it and owns layout. Recreate on width/orientation changes.
- `makeNativeLoader(configuration:)` returns a retained-by-host GoogleNativeAdLoader using the same request gate and presenter.

### Banner and native

`GoogleBannerAd.view` is the UIKit container; `width` records its configured width in points; `state` reports waterfall load state. `load(completion:)` performs initial floor selection and installs the successful SDK banner; `Result<CGFloat, AdsError>` supplies height in points. Give the container that height and width. Loading calls coalesce. The visible SDK banner manages subsequent refresh independently of initial floor selection. `clear()` removes rendering and cancels pending loads. An ad controller/view belongs in one hierarchy.

`GoogleNativeAdLoader.state` exposes initial loading status. `load(completion:)` returns a single consumed GoogleNativeAd. Concurrent loading returns loadInProgress; unlike a generic cache load, it never hands one resource to multiple waiting callers. `clear()` cancels pending loading. Delivered resources belong to the host.

`GoogleNativeAd.makeView()` creates one UIKit asset-registered view with attribution, media, headline, body, advertiser, icon and CTA. A second call throws invalidConfiguration. The view owns SDK click/AdChoices behavior. Use it in one hierarchy and provide container sizing. There is no native layout/SDK object customization API in this initial version.

`GoogleTestAdUnitIDs` provides five static strings for interstitial/appOpen/rewarded/adaptive banner/native demos. These are development IDs only. They are not your app ID, real high-floor units, or production release configuration.

`IOSAdsKitGoogleMobileAdsModule` is an empty namespace marker to allow the driver product's conditional build on a non-iOS test host. It has no runtime ad capability outside iOS.
