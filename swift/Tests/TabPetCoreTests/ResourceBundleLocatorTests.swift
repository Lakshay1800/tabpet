import XCTest

import TabPetCore

private final class LocatorTestToken {}

/// Proves the locator never traps (unlike Bundle.module) when the bundle
/// name it's asked for doesn't exist anywhere.
final class ResourceBundleLocatorTests: XCTestCase {
    func testMissingBundleNameReturnsNilWithoutTrapping() {
        let bundle = ResourceBundleLocator.find(
            bundleName: "TabPet_DoesNotExist.bundle",
            tokenType: LocatorTestToken.self
        )
        XCTAssertNil(bundle)
    }
}
