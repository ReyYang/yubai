// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Yubai",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "YubaiCore", targets: ["YubaiCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.1")
    ],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "YubaiCore", dependencies: [
            "CArchive",
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            .product(name: "_CryptoExtras", package: "swift-crypto", condition: .when(platforms: [.linux]))
        ], resources: [.copy("Resources/brand-icons.json")]),
        .testTarget(
            name: "YubaiCoreTests",
            dependencies: ["YubaiCore"],
            path: "Tests/YubaiCoreTests", // SampleData is a test fixture, never part of the app/core product.
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)

#if !os(Linux)
package.products.append(.executable(name: "YubaiDesktop", targets: ["YubaiApp"]))
package.targets.append(.executableTarget(
    name: "YubaiApp",
    dependencies: ["YubaiCore"],
    exclude: ["Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy", "Yubai-iCloud.entitlements",
              "Yubai-macOS.entitlements", "Yubai-macOS-iCloud.entitlements", "Yubai-AppGroup.entitlements", "Yubai-iCloud-AppGroup.entitlements"]
))
#endif
