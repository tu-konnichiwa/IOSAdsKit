/// Stable failures. SDK errors are mapped at the driver boundary.
public enum AdsError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case loadFailed(message: String)
    case presentationFailed(message: String)
    case timedOut
    case cancelled
    case adsDisabled
    case loadInProgress
}

/// Ordered waterfall: optional high floor first, mandatory normal ID second.
/// Empty/whitespace IDs are rejected; equal IDs are requested only once.
public struct AdUnitIDs: Equatable, Sendable {
    public let highFloorAdUnitID: String?
    public let normalAdUnitID: String

    public init(highFloorAdUnitID: String? = nil, normalAdUnitID: String) throws {
        let normal = Self.normalize(normalAdUnitID)
        guard !normal.isEmpty else {
            throw AdsError.invalidConfiguration("normalAdUnitID must not be empty")
        }
        let high = highFloorAdUnitID.map(Self.normalize)
        guard high == nil || high?.isEmpty == false else {
            throw AdsError.invalidConfiguration("Omit highFloorAdUnitID instead of passing an empty ID")
        }
        self.normalAdUnitID = normal
        self.highFloorAdUnitID = high == normal ? nil : high
    }

    private static func normalize(_ value: String) -> String {
        String(value.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }

    public var attempts: [(floor: AdFloor, adUnitID: String)] {
        var result: [(AdFloor, String)] = []
        if let highFloorAdUnitID { result.append((.high, highFloorAdUnitID)) }
        result.append((.normal, normalAdUnitID))
        return result
    }
}

public enum AdFloor: Equatable, Sendable { case high, normal }
public enum FullScreenAdFormat: Hashable, Sendable { case interstitial, appOpen, rewarded }
public enum AdRefreshPolicy: Equatable, Sendable { case afterPresentation, manual }

/// The caller owns placement names, independent of screen/controller types.
public struct AdPlacement: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public static let splash: Self = "splash"
    public static let common: Self = "common"
    public static let appOpen: Self = "appOpen"
}

/// All durations are seconds. Each floor has its own bounded timeout.
public struct AdLoadConfiguration: Equatable, Sendable {
    public let adUnitIDs: AdUnitIDs
    public let cacheLifetime: Double
    public let loadTimeout: Double

    public init(adUnitIDs: AdUnitIDs, cacheLifetime: Double = 3_600, loadTimeout: Double = 30) throws {
        guard cacheLifetime.isFinite, cacheLifetime > 0,
              loadTimeout.isFinite, loadTimeout > 0, loadTimeout <= 300 else {
            throw AdsError.invalidConfiguration("Cache lifetime must be positive; load timeout must be in (0, 300] seconds")
        }
        self.adUnitIDs = adUnitIDs
        self.cacheLifetime = cacheLifetime
        self.loadTimeout = loadTimeout
    }
}

/// Policies belong to a placement; no app or screen-specific configuration is built in.
public struct FullScreenAdConfiguration: Equatable, Sendable {
    public let format: FullScreenAdFormat
    public let load: AdLoadConfiguration
    public let refreshPolicy: AdRefreshPolicy
    public let minimumInterval: Double
    public let minimumBackgroundDuration: Double
    public let allowsColdStart: Bool

    public init(
        format: FullScreenAdFormat,
        adUnitIDs: AdUnitIDs,
        refreshPolicy: AdRefreshPolicy = .afterPresentation,
        minimumInterval: Double = 10,
        minimumBackgroundDuration: Double = 0,
        allowsColdStart: Bool = true,
        cacheLifetime: Double? = nil,
        loadTimeout: Double = 30
    ) throws {
        guard minimumInterval.isFinite, minimumInterval >= 0,
              minimumBackgroundDuration.isFinite, minimumBackgroundDuration >= 0 else {
            throw AdsError.invalidConfiguration("Minimum durations must be finite and nonnegative")
        }
        let lifetime = cacheLifetime ?? (format == .appOpen ? 14_400 : 3_600)
        guard format != .appOpen || lifetime <= 14_400 else {
            throw AdsError.invalidConfiguration("App-open ads must expire within four hours")
        }
        self.format = format
        self.load = try AdLoadConfiguration(adUnitIDs: adUnitIDs, cacheLifetime: lifetime, loadTimeout: loadTimeout)
        self.refreshPolicy = refreshPolicy
        self.minimumInterval = minimumInterval
        self.minimumBackgroundDuration = minimumBackgroundDuration
        self.allowsColdStart = allowsColdStart
    }
}

/// Reward is delivered only on the SDK's earned-reward event, never just on dismissal.
public struct AdReward: Equatable, Sendable {
    public let amount: Double
    public let type: String
    public init(amount: Double, type: String) { self.amount = amount; self.type = type }
}
