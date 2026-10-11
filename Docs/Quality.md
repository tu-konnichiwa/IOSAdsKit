# Verification and release readiness

Verified locally on 2026-10-11 with Xcode 26.4, Swift 6 language mode and resolved Google Mobile Ads 13.4.0 / UMP 3.1.0. The manifest now accepts `13.4.0..<14.0.0`; these runtime/build results cover the recorded 13.4.0 resolution.

## Actual executed results

| Check | Result |
|---|---|
| Core and driver-boundary Swift Testing tests | **31 tests / 5 suites passed**, zero failures |
| Xcode generic iOS driver build, arm64, iOS 15 deployment | **BUILD SUCCEEDED** |
| Xcode generic iOS Simulator driver build, arm64/x86_64 | **BUILD SUCCEEDED** |
| Examples/AdsIntegration.swift typecheck for iOS 15 | Passed, compiler exit 0 |
| Core Domain/Application framework-import scan | No framework/vendor imports |
| Source/documentation reference-name scan | No reference project/library names present |
| Working-scope whitespace check | Passed |

The simulator check is a **build**, not an executed simulator ad session. The generic iOS check builds the package's objects with SDK dependencies; it is not a signed installed app. Real ad delivery, native/banners' rendered appearance, clicks, reward mediation timing, consent forms and navigation require host app/device validation. No revenue, performance benchmark, or release compatibility guarantee is inferred from build success.

Policy tests use fake SDK loaders and virtual monotonic time. The platform scheduler test verifies zero-delay enqueue and idempotent cancellation without a timing sleep. Driver-boundary tests exercise diagnostic normalization, cancellation, network timeout, blank errors and distinct presentation failures using deterministic Foundation errors. SDK delegate wiring is compiler-checked against actual frameworks, but not executed by these host tests.

The final coverage run reports 99.38% line coverage for the core's Domain/Application/Runtime files. This narrow metric excludes UIKit/Google SDK execution and must not be interpreted as coverage of the driver or installed-app behavior.

Package binaries may emit upstream umbrella-header warnings for Beta headers. Their origin is GoogleMobileAds.framework, rather than IOSAdsKit source. Do not suppress them globally or claim a warning-free dependency build. Newly resolved SDK versions need a compatibility check.

## Review findings and fixes

- Replaced the clock's iOS 16-only sleep API with the cancellable nanosecond API compatible with the iOS 15 deployment target.
- Invalidated load attempt identity before driver cancellation, covering synchronous, duplicate and stale callbacks.
- Established presentation ownership before calling the driver; separated the visible resource/completion from load cache state.
- Kept the cross-format presentation lock until a real terminal event; frequency records only the first presented event.
- Deduplicated rewards and rejected reward events on non-rewarded formats.
- Cleared cache on disable/cancellation and prevented late load callbacks from reviving it.
- Removed private-field reflection from the banner mechanism. The successful view and size flow through explicit driver ownership; banner sizes use the SDK's public opaque-size conversion.
- Validated adaptive banner size at creation and reused the same size for both floor attempts. Missing presenter errors are explicit, not implicit global UI discovery.
- Made native loading single-consumer and rendering one-use to prevent the same resource being mounted multiple times.
- Added cancellation-token cleanup on deallocation and a behavior test for release of the full-screen resource/client without a retain cycle.
- Found a RULE-022 test gap for driver failure mapping, centralized the boundary mapping and fixed it with four tests. No unresolved architecture-rule violation was identified in the final scoped review.
- Published accurate installation, ownership, timing, errors and versioning documentation, with a compiled realistic integration example.

## Prioritized gap analysis

No known P0 defect was identified by the executed checks; device behavior is still unverified.

| Priority | Missing / improvement | Why and expected impact | Recommended action / timing | Complexity |
|---|---|---|---|---|
| P1 | Installed-app/device ad and consent verification | Compilation cannot prove delegate/lifecycle completion, layout, AdChoices taps or mediated rewards. Validation reduces release crash/UX risk. | Before release: run dedicated test units on a physical phone and tablet; test cold/warm starts, rotation, background, no-fill/offline, invalid presenter, consent/subscription changes, dismissal and reward. Add an iOS smoke host with repeatable scenarios. | Medium |
| P1 | License and publication metadata | A reusable repository needs explicit distribution rights and release ownership. This makes adoption and redistribution clear. | Before publishing: maintainer chooses the license, reviews third-party notices, creates the standalone repository/release tag and records a support/security contact. No license has been invented on the owner's behalf. | Low |
| P1 (conditional) | Server-side reward verification configuration | Local callbacks are insufficient for security-sensitive value. Authoritative verification prevents fraudulent credits. | Implement a driver SSV configuration API plus trusted backend verification **before** using rewards for protected value; defer for noncritical local UX rewards. | Medium–High |
| P2 | Revenue/impression and request diagnostics | Final state alone does not expose recovered high-floor errors, paid events or mediation traces. Typed observability would improve tuning/support. | Defer until a concrete telemetry consumer exists; add a small event contract with tested one-shot semantics and no SDK types in core. | Medium |
| P2 | Native rendering/custom asset layouts and batch ownership | One standard native layout does not fit every host or list. Explicit layout/pool ownership can improve layout flexibility and loading latency. | Defer until host requirements establish needed templates or batching; preserve single-use ownership and add device layout checks. | Medium |
| P2 | SDK upgrade matrix and release automation | The flexible 13.x range permits host dependency updates, but later SDK versions have not yet been verified here. Automation improves upgrade/release confidence. | Run the supplied CI after repository publication; periodically test a newer SDK in a reviewed change with both builds, examples and device smoke checks. | Medium |
| P3 | Additional networks, rewarded-interstitial, standalone native scenes | These capabilities may be useful but have no current requirement; premature layers increase API cost. | Defer until requested. Add drivers/formats against demonstrated use cases instead of speculative interfaces. | High |

## Most valuable next step

Run the installed-app/device matrix with test-enabled high-floor and normal units, including high no-fill → normal success. Then choose the distribution license and create the first release. The supplied CI workflow has local equivalent commands verified, but no hosted GitHub run was executed or claimed.
