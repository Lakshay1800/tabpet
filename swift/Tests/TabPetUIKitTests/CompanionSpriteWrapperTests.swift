#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import XCTest

import TabPetCore
@testable import TabPetUIKit

@MainActor
final class CompanionSpriteWrapperTests: XCTestCase {
    private final class SizeModel: ObservableObject {
        @Published var size: CGFloat = 88
    }

    private struct Host: View {
        let companionID: String
        @ObservedObject var model: SizeModel
        var body: some View {
            CompanionSprite(companionID: companionID, size: model.size)
        }
    }

    private func findSpriteView(in view: UIView) -> CompanionSpriteView? {
        if let sprite = view as? CompanionSpriteView { return sprite }
        for subview in view.subviews {
            if let found = findSpriteView(in: subview) { return found }
        }
        return nil
    }

    func testUpdateUIViewPushesAChangedSizeToTheUnderlyingView() {
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        CompanionRegistry.shared.register(profile)

        let model = SizeModel()
        let hosting = UIHostingController(rootView: Host(companionID: profile.id, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()

        guard let sprite = findSpriteView(in: hosting.view) else {
            return XCTFail("CompanionSpriteView not found in the hosted hierarchy")
        }
        XCTAssertEqual(sprite.size, 88)

        model.size = 54
        let deadline = Date().addingTimeInterval(2)
        while sprite.size != 54 && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(sprite.size, 54, "updateUIView must push a changed size to the underlying view")
    }

    private struct WideTallHost: View {
        let companionID: String
        var body: some View {
            VStack {
                CompanionSprite(companionID: companionID, size: 54)
                Text("padding that widens and heightens the stack well past 54pt")
            }
            .frame(width: 300, height: 300)
        }
    }

    func testTheSpriteViewStaysSizeBySizeInsideAWiderTallerStack() {
        let profile = SpriteTestFixtures.makeFixtureProfile(cellSize: 20)
        CompanionRegistry.shared.register(profile)

        let hosting = UIHostingController(rootView: WideTallHost(companionID: profile.id))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()

        guard let sprite = findSpriteView(in: hosting.view) else {
            return XCTFail("CompanionSpriteView not found in the hosted hierarchy")
        }
        XCTAssertEqual(
            sprite.frame.size,
            CGSize(width: 54, height: 54),
            "content hugging/compression resistance must keep the view pinned to size x size, not stretched by the stack"
        )
    }
}
#endif
