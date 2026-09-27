import TabPetAnimalBird
import TabPetAnimalCat
import TabPetAnimalPanda
import TabPetAnimalRaccoon
import TabPetAnimalSquirrel
import TabPetAnimalTurtle
import TabPetCore

/// Umbrella over the six built-in animal targets - importing this (or
/// `registerAll`) bundles every sprite sheet. A host that wants fewer
/// animals depends on the individual `TabPetAnimal<Name>` products instead.
public enum TabPetAnimals {
    /// the order registerBuiltinCompanions registers them in
    /// (packages/tabpet/src/animals/all.ts) - conformance/animals.json's
    /// case order matches this too.
    public static let profiles: [CompanionProfile] = [
        TabPetAnimalPanda.profile,
        TabPetAnimalCat.profile,
        TabPetAnimalTurtle.profile,
        TabPetAnimalRaccoon.profile,
        TabPetAnimalBird.profile,
        TabPetAnimalSquirrel.profile,
    ]

    @MainActor
    public static func registerAll(in registry: CompanionRegistry = .shared) {
        TabPetAnimalPanda.register(in: registry)
        TabPetAnimalCat.register(in: registry)
        TabPetAnimalTurtle.register(in: registry)
        TabPetAnimalRaccoon.register(in: registry)
        TabPetAnimalBird.register(in: registry)
        TabPetAnimalSquirrel.register(in: registry)
    }
}
