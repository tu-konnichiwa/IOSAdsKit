import Foundation
import IOSAdsKit

/// Framework boundary mapping shared by all ad formats. Client code can rely on
/// cancellation/timeout semantics without inspecting platform error domains or codes.
enum GoogleAdErrorMapper {
    static func loading(_ error: any Error) -> AdsError {
        if error is CancellationError { return .cancelled }
        let platformError = error as NSError
        if platformError.domain == NSURLErrorDomain, platformError.code == NSURLErrorTimedOut {
            return .timedOut
        }
        return .loadFailed(message: message(error, fallback: "Ad request failed"))
    }

    static func presentation(_ error: any Error) -> AdsError {
        .presentationFailed(message: message(error, fallback: "Ad presentation failed"))
    }

    private static func message(_ error: any Error, fallback: String) -> String {
        let value = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
