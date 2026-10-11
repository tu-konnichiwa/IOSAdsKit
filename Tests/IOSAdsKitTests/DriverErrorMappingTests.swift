import Foundation
import Testing
import IOSAdsKit
@testable import IOSAdsKitGoogleMobileAds

struct DriverErrorMappingTests {
    @Test func loadFailureProvidesStableNormalizedDiagnostic() {
        let error = NSError(domain: "vendor.failure", code: 71, userInfo: [NSLocalizedDescriptionKey: " no fill\n"])
        #expect(GoogleAdErrorMapper.loading(error) == .loadFailed(message: "no fill"))
    }

    @Test func cancellationAndNetworkTimeoutRemainActionable() {
        #expect(GoogleAdErrorMapper.loading(CancellationError()) == .cancelled)
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(GoogleAdErrorMapper.loading(timeout) == .timedOut)
        let unrelated = NSError(domain: "different.domain", code: NSURLErrorTimedOut,
                                userInfo: [NSLocalizedDescriptionKey: "vendor failure"])
        #expect(GoogleAdErrorMapper.loading(unrelated) == .loadFailed(message: "vendor failure"))
    }

    @Test func blankErrorsAreNeverReportedAsBlankFailures() {
        let blank = NSError(domain: "vendor.failure", code: 0, userInfo: [NSLocalizedDescriptionKey: " \n "])
        #expect(GoogleAdErrorMapper.loading(blank) == .loadFailed(message: "Ad request failed"))
        #expect(GoogleAdErrorMapper.presentation(blank) == .presentationFailed(message: "Ad presentation failed"))
    }

    @Test func presentationErrorsStayDistinctFromLoadFailures() {
        let error = NSError(domain: "vendor.presentation", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "already consumed"])
        #expect(GoogleAdErrorMapper.presentation(error) == .presentationFailed(message: "already consumed"))
    }
}
