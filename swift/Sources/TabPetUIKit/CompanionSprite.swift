#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

import TabPetCore

/// SwiftUI wrapper around `CompanionSpriteView`. `intrinsicContentSize`
/// already reports `size x size`, so this never reaches for the iOS 16+
/// `sizeThatFits(_:uiView:context:)` - the package's floor is iOS 15.1.
public struct CompanionSprite: UIViewRepresentable {
    private let companionID: String
    private let pose: PupPose
    private let busy: Bool
    private let facing: Facing
    private let size: CGFloat
    private let pressLabel: String?
    private let onPress: (() -> Void)?
    private let onSitDone: (() -> Void)?
    private let onHaptic: ((HapticKind) -> Void)?
    private let onError: ((Error, String) -> Void)?

    public init(
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        pose: PupPose = .idle,
        busy: Bool = false,
        facing: Facing = .right,
        size: CGFloat = 88,
        pressLabel: String? = nil,
        onPress: (() -> Void)? = nil,
        onSitDone: (() -> Void)? = nil,
        onHaptic: ((HapticKind) -> Void)? = nil,
        onError: ((Error, String) -> Void)? = nil
    ) {
        self.companionID = companionID
        self.pose = pose
        self.busy = busy
        self.facing = facing
        self.size = size
        self.pressLabel = pressLabel
        self.onPress = onPress
        self.onSitDone = onSitDone
        self.onHaptic = onHaptic
        self.onError = onError
    }

    public func makeUIView(context: Context) -> CompanionSpriteView {
        // `onError` at construction, not only through `applyState` below -
        // a profile missing at the very first resolve (inside init) would
        // otherwise report to a still-nil handler and be lost for good.
        let view = CompanionSpriteView(companionID: companionID, size: size, onError: onError)
        applyState(to: view)
        return view
    }

    public func updateUIView(_ uiView: CompanionSpriteView, context: Context) {
        if uiView.companionID != companionID {
            uiView.companionID = companionID
        }
        applyState(to: uiView)
    }

    private func applyState(to view: CompanionSpriteView) {
        view.size = size
        view.pose = pose
        view.isBusy = busy
        view.facing = facing
        view.pressAccessibilityLabel = pressLabel
        view.onPress = onPress
        view.onSitDone = onSitDone
        view.onHaptic = onHaptic
        view.onError = onError
    }
}
#endif
