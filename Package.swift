// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yubai",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "YubaiCore", targets: ["YubaiCore"]),
        .executable(name: "YubaiDesktop", targets: ["YubaiApp"])
    ],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "YubaiCore", dependencies: ["CArchive"]),
        .executableTarget(
            name: "YubaiApp",
            dependencies: ["YubaiCore"],
            exclude: ["Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy", "Yubai-iCloud.entitlements",
                      "Yubai-macOS.entitlements", "Yubai-macOS-iCloud.entitlements"]
        ),
        .testTarget(
            name: "YubaiCoreTests",
            dependencies: ["YubaiCore"],
            path: "Tests/YubaiCoreTests", // SampleData is a test fixture, never part of the app/core product.
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
