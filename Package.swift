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
        .library(name: "TabPetAnimalPanda", targets: ["TabPetAnimalPanda"]),
        .library(name: "TabPetAnimalCat", targets: ["TabPetAnimalCat"]),
        .library(name: "TabPetAnimalTurtle", targets: ["TabPetAnimalTurtle"]),
        .library(name: "TabPetAnimalRaccoon", targets: ["TabPetAnimalRaccoon"]),
        .library(name: "TabPetAnimalBird", targets: ["TabPetAnimalBird"]),
        .library(name: "TabPetAnimalSquirrel", targets: ["TabPetAnimalSquirrel"]),
        .library(name: "TabPetAnimals", targets: ["TabPetAnimals"]),
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
            path: "swift/Tests/TabPetCoreTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
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
        // Each animal target depends on TabPetCore only, so importing one
        // never bundles the others (tools/swift-isolation-check.sh). Assets
        // are .copy, not .process - byte identity with packages/tabpet/assets
        // is checked by tools/swift-asset-check.sh, never left to the build.
        .target(
            name: "TabPetAnimalPanda",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalPanda",
            resources: [
                .copy("panda-idle-sprite.png"),
                .copy("panda-run-sprite.png"),
                .copy("panda-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimalCat",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalCat",
            resources: [
                .copy("cat-idle-sprite.png"),
                .copy("cat-run-sprite.png"),
                .copy("cat-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimalTurtle",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalTurtle",
            resources: [
                .copy("turtle-idle-sprite.png"),
                .copy("turtle-run-sprite.png"),
                .copy("turtle-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimalRaccoon",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalRaccoon",
            resources: [
                .copy("raccoon-idle-sprite.png"),
                .copy("raccoon-run-sprite.png"),
                .copy("raccoon-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimalBird",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalBird",
            resources: [
                .copy("bird-idle-sprite.png"),
                .copy("bird-run-sprite.png"),
                .copy("bird-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimalSquirrel",
            dependencies: ["TabPetCore"],
            path: "swift/Sources/TabPetAnimalSquirrel",
            resources: [
                .copy("squirrel-idle-sprite.png"),
                .copy("squirrel-run-sprite.png"),
                .copy("squirrel-sit-sprite.png"),
                .copy("LICENSE-ART.md"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "TabPetAnimals",
            dependencies: [
                "TabPetCore",
                "TabPetAnimalPanda",
                "TabPetAnimalCat",
                "TabPetAnimalTurtle",
                "TabPetAnimalRaccoon",
                "TabPetAnimalBird",
                "TabPetAnimalSquirrel",
            ],
            path: "swift/Sources/TabPetAnimals",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "TabPetAnimalsTests",
            dependencies: ["TabPetAnimals"],
            path: "swift/Tests/TabPetAnimalsTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
