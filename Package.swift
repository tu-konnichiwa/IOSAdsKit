// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IOSAdsKit",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "IOSAdsKit", targets: ["IOSAdsKit"]),
        .library(name: "IOSAdsKitGoogleMobileAds", targets: ["IOSAdsKitGoogleMobileAds"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.4.0"
        )
    ],
    targets: [
        .target(name: "IOSAdsKit"),
        .target(
            name: "IOSAdsKitGoogleMobileAds",
            dependencies: [
                "IOSAdsKit",
                .product(
                    name: "GoogleMobileAds",
                    package: "swift-package-manager-google-mobile-ads",
                    condition: .when(platforms: [.iOS])
                )
            ]
        ),
        .testTarget(name: "IOSAdsKitTests", dependencies: ["IOSAdsKit", "IOSAdsKitGoogleMobileAds"])
    ],
    swiftLanguageModes: [.v6]
)
