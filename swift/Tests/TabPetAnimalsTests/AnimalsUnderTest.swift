import TabPetAnimalBird
import TabPetAnimalCat
import TabPetAnimalPanda
import TabPetAnimalRaccoon
import TabPetAnimalSquirrel
import TabPetAnimalTurtle
import TabPetCore

/// One row per shipped animal, built from each target's public API only
/// (never `Bundle.module` or a testing-only accessor) - both test classes in
/// this file's target read from this one list instead of rebuilding it.
struct AnimalUnderTest {
    let id: String
    let profile: CompanionProfile
    let attribution: String
    let licenseText: String
    /// SwiftPM's naming convention for this target's generated resource
    /// bundle - what the locator (used inside each animal's own `profile`)
    /// is expected to have found.
    let expectedBundleName: String
}

let animalsUnderTest: [AnimalUnderTest] = [
    AnimalUnderTest(
        id: "panda", profile: TabPetAnimalPanda.profile, attribution: TabPetAnimalPanda.attribution,
        licenseText: TabPetAnimalPanda.licenseText, expectedBundleName: "TabPet_TabPetAnimalPanda.bundle"
    ),
    AnimalUnderTest(
        id: "cat", profile: TabPetAnimalCat.profile, attribution: TabPetAnimalCat.attribution,
        licenseText: TabPetAnimalCat.licenseText, expectedBundleName: "TabPet_TabPetAnimalCat.bundle"
    ),
    AnimalUnderTest(
        id: "turtle", profile: TabPetAnimalTurtle.profile, attribution: TabPetAnimalTurtle.attribution,
        licenseText: TabPetAnimalTurtle.licenseText, expectedBundleName: "TabPet_TabPetAnimalTurtle.bundle"
    ),
    AnimalUnderTest(
        id: "raccoon", profile: TabPetAnimalRaccoon.profile, attribution: TabPetAnimalRaccoon.attribution,
        licenseText: TabPetAnimalRaccoon.licenseText, expectedBundleName: "TabPet_TabPetAnimalRaccoon.bundle"
    ),
    AnimalUnderTest(
        id: "bird", profile: TabPetAnimalBird.profile, attribution: TabPetAnimalBird.attribution,
        licenseText: TabPetAnimalBird.licenseText, expectedBundleName: "TabPet_TabPetAnimalBird.bundle"
    ),
    AnimalUnderTest(
        id: "squirrel", profile: TabPetAnimalSquirrel.profile, attribution: TabPetAnimalSquirrel.attribution,
        licenseText: TabPetAnimalSquirrel.licenseText, expectedBundleName: "TabPet_TabPetAnimalSquirrel.bundle"
    ),
]
