/// Ad values are caller-owned and can be opaque handles. Each supplied ad is inserted
/// at most once; no resource is rendered twice or recycled within the same list.
public enum AdListItem<Content, Ad> {
    case content(Content, originalIndex: Int)
    case ad(Ad, adIndex: Int)
}

extension AdListItem: Equatable where Content: Equatable, Ad: Equatable {}
extension AdListItem: Sendable where Content: Sendable, Ad: Sendable {}

public enum AdList {
    /// Inserts after `startAfter` content items, then every `spacing` content items.
    /// Values use content counts, independent of inserted rows. No ads follow an empty list.
    /// A nil limit uses all supplied ads. Negative counts and zero spacing are rejected.
    public static func inserting<Content, Ad>(
        _ ads: [Ad], into content: [Content], startAfter: Int = 4, spacing: Int = 4, limit: Int? = nil
    ) throws -> [AdListItem<Content, Ad>] {
        guard startAfter >= 0, spacing > 0, limit.map({ $0 >= 0 }) ?? true else {
            throw AdsError.invalidConfiguration("startAfter and limit must be nonnegative; spacing must be positive")
        }
        guard !content.isEmpty else { return [] }
        let count = min(ads.count, limit ?? ads.count)
        var result: [AdListItem<Content, Ad>] = []
        var adIndex = 0
        func appendAd() {
            guard adIndex < count else { return }
            result.append(.ad(ads[adIndex], adIndex: adIndex))
            adIndex += 1
        }
        if startAfter == 0 { appendAd() }
        for (index, item) in content.enumerated() {
            result.append(.content(item, originalIndex: index))
            let consumed = index + 1
            if consumed >= startAfter, (consumed - startAfter) % spacing == 0 { appendAd() }
        }
        return result
    }
}
