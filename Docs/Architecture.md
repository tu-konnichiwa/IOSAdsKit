# Architecture decision: isolate ad policy from the SDK

Status: accepted for the initial 0.1.0 API.

## Alternatives

1. A single SDK-coupled target with a manager/slot/waterfall for each format. It gives a small install surface, but duplicates concurrency, deadlines and cache rules; SDK/UI dependencies prevent policy tests on a plain host.
2. A pure Swift policy target and one iOS SDK driver target. This introduces one meaningful physical boundary, while allowing all formats to share a generic waterfall and full-screen admission policy. Tests do not need an SDK session, simulator or network.

Choose alternative 2. Two products are justified by test/build isolation and dependency enforcement. A target per layer or ad format adds no current value. For SDK versioning, an exact 13.4.0 requirement gives a fixed baseline but conflicts with hosts adopting later compatible updates. Choose `from: "13.4.0"` instead: it accepts `13.4.0..<14.0.0`, permitting minor/patch upgrades while excluding the next major. The development lockfile records the tested resolution; it does not impose an exact SDK requirement on consuming apps. Validate newly resolved SDK versions before release.

## Responsibility and dependency direction

```text
Host composition / GoogleAds
  ├─ Google full-screen, native, banner drivers → IOSAdsKit application ports
  └─ SystemAdScheduler (Foundation/Task driver) → AdScheduler port
                                               ↓
                                      FullScreenAds / AdWaterfall
                                               ↓
                                      Pure domain configuration
```

Domain and Application import only the Swift standard library. Foundation time and task mechanics live in Runtime. UIKit, SwiftUI and Google types do not enter Application/Domain. Host composition owns scene context, subscription/remote-config decisions, consent and tracking. There is no service locator or global client singleton.

AdWaterfall owns ordered floor attempts, load deadlines, logical cancellation, cache expiry and callback coalescing. It invalidates an attempt identity before cancelling its driver, so synchronous cancellation, duplicate events and late SDK completions cannot revive stale resources. Each attempt has its own timeout; high-floor failure/timeout tries normal exactly once. Cancellation stops without fallback. ID normalization/deduplication has one domain owner.

FullScreenAds owns admission, frequency, app-open background policy and a single presentation reservation across all full-screen formats in its scope. It keeps the visible ad separate from cache/load state. Loading or clearing a placement during presentation cannot discard its terminal callback. Frequencies are scoped to format and shared across placements; they start at the presented event. Reward is an event, separate from dismissal, and is accepted at most once per rewarded presentation. Reentrant client callbacks see the reservation released and automatic refresh already started.

SDK drivers share one tested failure mapper into AdsError (including cancellation and network timeout), own delegates, and release request completions/delegates when logically cancelled. Cancellation tokens also arrange MainActor cleanup on deallocation. SDK network work may be non-cancellable; its eventual result is ignored. Native requests are single-consumer, preventing a loaded ad from being handed to several views. Native view registration is entirely in the SDK driver.

## Contracts and trade-offs

- All state and callbacks are MainActor-isolated. No locks or bidirectional reactive plumbing are needed.
- Cache time is monotonic and measured from successful load. App-open TTL is capped at four hours; full-screen defaults are one hour otherwise.
- Generic cache load calls coalesce. Native parallel loads fail explicitly because native resources must have a single consumer.
- No automatic retry loop beyond high → normal: the host explicitly retries final failures. Default 30 seconds per floor bounds a waterfall at 60 seconds.
- No presentation watchdog releases a visible ad: releasing the lock without a real terminal SDK event could permit overlapping full-screen content. A driver must deliver dismissal/failure; on-device verification remains a release check.
- There is no modal loading controller. The host can render loading state, and preloaded presentation has no navigation side effects.
- Disabled is the default. Use GoogleAds.setAdsEnabled for the integrated driver scope; directly controlling FullScreenAds only controls full-screen resources.
- Host-delivered native ads belong to the host. Consent/subscription changes require the host to remove their views as well as disabling future requests.
- SPM still resolves the package's binary dependencies for core tests, but the core target neither imports nor links those frameworks on macOS. The tests themselves use no network or device; the first dependency resolution needs network access.
