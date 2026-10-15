// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yubai",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "YubaiCore", targets: ["YubaiCore"]),
        .library(name: "YubaiLocalLLM", targets: ["YubaiLocalLLM"]),
        .executable(name: "YubaiDesktop", targets: ["YubaiApp"])
    ],
    dependencies: [
        // Versioned SPM wrapper around official llama.cpp XCFramework (Metal). Pin major for App Store builds.
        .package(url: "https://github.com/mattt/llama.swift", exact: "2.10549.0")
    ],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "YubaiCore", dependencies: ["CArchive"]),
        .target(
            name: "YubaiLocalLLM",
            dependencies: [
                "YubaiCore",
                .product(name: "LlamaSwift", package: "llama.swift")
            ]
        ),
        .executableTarget(
            name: "YubaiApp",
            dependencies: ["YubaiCore", "YubaiLocalLLM"],
            exclude: ["Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy"]
        ),
        .testTarget(
            name: "YubaiCoreTests",
            dependencies: ["YubaiCore", "YubaiLocalLLM"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
