// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabPet",
    platforms: [
        .iOS("15.1"),
        .macOS(.v12),
    ],
    products: [
        .library(name: "TabPetCore", targets: ["TabPetCore"]),
        .library(name: "TabPetUIKit", targets: ["TabPetUIKit"]),
    ],
    targets: [
        .target(
            name: "TabPetCore",
            path: "swift/Sources/TabPetCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TabPetCoreTests",
            dependencies: ["TabPetCore"],
            path: "swift/Tests/TabPetCoreTests"
        ),
        // Never "TabPet" alone: the Expo pod's Swift module already claims that name.
        .target(
            name: "TabPetUIKit",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetUIKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TabPetUIKitTests",
            dependencies: ["TabPetUIKit"],
            path: "swift/Tests/TabPetUIKitTests"
        ),
    ]
)
