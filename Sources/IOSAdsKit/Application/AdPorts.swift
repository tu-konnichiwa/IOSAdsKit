/// Cancellation is idempotent and must not invoke any further successful completion.
@MainActor
public protocol AdCancellation: AnyObject {
    func cancel()
}

/// Monotonic time and cancellable deadlines. Callbacks run on MainActor.
/// Schedule must enqueue work, even for zero delay; it must not call inline.
@MainActor
public protocol AdScheduler: AnyObject {
    var now: Double { get }
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any AdCancellation
}

public enum FullScreenAdEvent: Equatable, Sendable {
    case presented
    case earnedReward(AdReward)
    case dismissed
    case failed(AdsError)
}

/// One-use loaded resource. Drivers own platform context and must finish with
/// dismissed or failed. Events may arrive synchronously during present.
@MainActor
public protocol FullScreenAd: AnyObject {
    func present(onEvent: @escaping @MainActor (FullScreenAdEvent) -> Void)
}

/// The application sees only stable ad resources and errors, never SDK/UI objects.
@MainActor
public protocol FullScreenAdLoading: AnyObject {
    func load(
        format: FullScreenAdFormat,
        adUnitID: String,
        completion: @escaping @MainActor (Result<any FullScreenAd, AdsError>) -> Void
    ) -> any AdCancellation
}
