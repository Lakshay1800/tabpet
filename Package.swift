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
    ]
)
