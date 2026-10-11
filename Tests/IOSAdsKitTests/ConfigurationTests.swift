import Testing
import IOSAdsKit

struct ConfigurationTests {
    @Test func idsNormalizeValidateAndDeduplicate() throws {
        let ids = try AdUnitIDs(highFloorAdUnitID: " high\n", normalAdUnitID: " normal ")
        #expect(ids.highFloorAdUnitID == "high")
        #expect(ids.normalAdUnitID == "normal")
        #expect(try AdUnitIDs(highFloorAdUnitID: "same", normalAdUnitID: "same").attempts.count == 1)
        #expect(throws: AdsError.self) { try AdUnitIDs(normalAdUnitID: "\n ") }
        #expect(throws: AdsError.self) { try AdUnitIDs(highFloorAdUnitID: " ", normalAdUnitID: "normal") }
    }

    @Test func durationsRejectInvalidValues() throws {
        let ids = try AdUnitIDs(normalAdUnitID: "normal")
        for duration in [0, -1, Double.nan, Double.infinity] {
            #expect(throws: AdsError.self) { try AdLoadConfiguration(adUnitIDs: ids, cacheLifetime: duration) }
            #expect(throws: AdsError.self) { try AdLoadConfiguration(adUnitIDs: ids, loadTimeout: duration) }
        }
        #expect(throws: AdsError.self) { try AdLoadConfiguration(adUnitIDs: ids, loadTimeout: 301) }
        #expect(throws: AdsError.self) {
            try FullScreenAdConfiguration(format: .appOpen, adUnitIDs: ids, cacheLifetime: 14_401)
        }
        #expect(try FullScreenAdConfiguration(format: .appOpen, adUnitIDs: ids).load.cacheLifetime == 14_400)
        for duration in [-1, Double.nan, Double.infinity] {
            #expect(throws: AdsError.self) {
                try FullScreenAdConfiguration(format: .interstitial, adUnitIDs: ids, minimumInterval: duration)
            }
            #expect(throws: AdsError.self) {
                try FullScreenAdConfiguration(format: .appOpen, adUnitIDs: ids, minimumBackgroundDuration: duration)
            }
        }
    }

    @Test func listInsertionPreservesContentAndNeverReusesAds() throws {
        let result = try AdList.inserting(["a", "b"], into: [0, 1, 2, 3, 4, 5], startAfter: 2, spacing: 2)
        #expect(result == [
            .content(0, originalIndex: 0), .content(1, originalIndex: 1), .ad("a", adIndex: 0),
            .content(2, originalIndex: 2), .content(3, originalIndex: 3), .ad("b", adIndex: 1),
            .content(4, originalIndex: 4), .content(5, originalIndex: 5)
        ])
        #expect(try AdList.inserting(["a"], into: [Int]()).isEmpty)
        #expect(try AdList.inserting(["a"], into: [1], startAfter: 0) == [.ad("a", adIndex: 0), .content(1, originalIndex: 0)])
        #expect(try AdList.inserting(["a"], into: [1], startAfter: 0, limit: 0) == [.content(1, originalIndex: 0)])
        #expect(try AdList.inserting(["a"], into: [1], startAfter: Int.max) == [.content(1, originalIndex: 0)])
        #expect(throws: AdsError.self) { try AdList.inserting(["a"], into: [1], spacing: 0) }
        #expect(throws: AdsError.self) { try AdList.inserting(["a"], into: [1], startAfter: -1) }
        #expect(throws: AdsError.self) { try AdList.inserting(["a"], into: [1], limit: -1) }
    }
}
