import Combine
import TabPetMotion
import XCTest

/// Proves the module's own `SequenceAnimation`/`MotionCancellable` names
/// don't shadow `Swift.Sequence`/`Combine.Cancellable` for a file that
/// imports both TabPetMotion (plainly, not `@testable`) and Combine - the
/// whole reason those two types were renamed away from `Sequence` and
/// `Cancellable`. If this file fails to compile, the rename didn't work.
extension Sequence where Element: Numeric {
    func summed() -> Element {
        reduce(0 as Element, +)
    }
}

func countElements(in sequence: some Sequence) -> Int {
    var count = 0
    for _ in sequence {
        count += 1
    }
    return count
}

final class NameCollisionCompileTests: XCTestCase {
    func testSequenceExtensionAndOpaqueParameterCompileAndRun() {
        XCTAssertEqual([1, 2, 3].summed(), 6)
        XCTAssertEqual(countElements(in: [1, 2, 3, 4]), 4)
    }

    func testCombineCancellableTypeNameIsUnshadowed() {
        var receivedValue: Int?
        let subscription: Combine.Cancellable = Just(7).sink { receivedValue = $0 }
        subscription.cancel()
        XCTAssertEqual(receivedValue, 7)
    }
}
