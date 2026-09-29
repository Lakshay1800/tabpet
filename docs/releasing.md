# Releasing

One git tag, `vX.Y.Z`, serves both the npm package and SwiftPM. SwiftPM reads its version from the tag. npm reads it from `packages/tabpet/package.json`. The two must name the same version, so a release checks that they do.

Nothing here is automated. CI checks the code; it does not tag or publish. Every step below is a person at a terminal.

`X.Y.Z` stands for the version being released. The number is the maintainer's call.

## Checklist

1. **Set the version.** `packages/tabpet/package.json` says `X.Y.Z`. The top heading of `CHANGELOG.md` is `## X.Y.Z` (rename `## Unreleased`). `bun.lock` records the workspace version too: run `bun install` and commit the lockfile with the rest. The examples that name a packed tarball, in `CONTRIBUTING.md` and `docs/integration.md`, carry a version too; bring them along. Land this on `main`.

2. **Check the commit that will be tagged.** On that commit, from the repository root:

   ```bash
   bun install --frozen-lockfile
   bun run check
   swift build
   swift test
   bash tools/swift-isolation-check.sh
   ```

   `bun run check` runs the leak check, typecheck, format check, lint, tests and fixture checks. `swift test` runs on macOS, so it leaves out the `TabPetUIKit` tests. CI runs those, and the demo build, on a simulator: `bash tools/swift-sim-test.sh` and `bash tools/swift-demo-build.sh`. Confirm the CI run for that commit on `main` is green:

   ```bash
   gh run list --workflow CI --branch main --limit 1
   ```

3. **Tag it and push the tag.**

   ```bash
   git checkout main
   git pull --ff-only
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   Check that the tag carries the version you meant:

   ```bash
   git show vX.Y.Z:packages/tabpet/package.json | grep '"version"'
   ```

4. **Publish to npm.** From `packages/tabpet`. The `prepublishOnly` script builds `build/` first.

   ```bash
   cd packages/tabpet
   npm publish
   ```

   Then confirm npm serves the version you tagged. It must print `X.Y.Z`:

   ```bash
   npm view react-native-tabpet version
   ```

5. **Check that SwiftPM resolves the tag.** In an empty scratch directory outside the repository, make `Package.swift`:

   ```swift
   // swift-tools-version: 5.9
   import PackageDescription

   let package = Package(
       name: "TagCheck",
       platforms: [.macOS(.v12)],
       dependencies: [
           .package(url: "https://github.com/Lakshay1800/tabpet", exact: "X.Y.Z"),
       ],
       targets: [
           .target(
               name: "TagCheck",
               dependencies: [
                   .product(name: "TabPetCore", package: "tabpet"),
                   .product(name: "TabPetAnimals", package: "tabpet"),
               ]
           ),
       ]
   )
   ```

   And one source file, `Sources/TagCheck/TagCheck.swift`:

   ```swift
   import TabPetAnimals

   public let animalCount = TabPetAnimals.profiles.count
   ```

   Then:

   ```bash
   swift package resolve
   swift build
   ```

   `resolve` must report `tabpet` at `X.Y.Z`. The build compiles the core, motion and animal targets on macOS. It does not build the `TabPetUIKit` views, which exist only on iOS; step 6 covers them.

6. **Check Xcode offers it.** In Xcode, File, Add Package Dependencies, paste `https://github.com/Lakshay1800/tabpet`. The version list must show `X.Y.Z`. Add `TabPetUIKit` and one animal to a scratch iOS app and build it for a simulator.

7. **When the two disagree.**

   - **The tag exists and npm has another version, or none.** Look at `packages/tabpet/package.json` on the tagged commit (the `git show` line in step 3). If it says `X.Y.Z`, the tag is right: publish that commit (`git checkout vX.Y.Z`, then step 4). If it says something else, the tag is on the wrong commit.
   - **npm has `X.Y.Z` and there is no tag.** Find the commit that was published, the one whose `package.json` says `X.Y.Z`, and tag it (step 3, with that commit in place of `main`).
   - **A tag is on the wrong commit.** If it was pushed minutes ago and nobody could have resolved it, delete it (`git push origin :refs/tags/vX.Y.Z`) and tag again. If anyone might have resolved it, leave it: SwiftPM projects that already resolved the tag keep the commit they got, and moving it changes what `exact:` means for the rest. Release the next patch version on both sides instead.
   - **npm has a version you did not mean to publish.** A published npm version number cannot be reused, even after an unpublish. Release the next patch version on both sides.
