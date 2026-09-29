#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

import TabPetCore

/// SwiftUI form of `CompanionPerchView`, for the tab bar of a `TabView`. Add
/// `.overlay { CompanionPerch(selection: tab, slotCount: 5).ignoresSafeArea() }`
/// to the tab view. Touches reach the bar and the content except on the pet.
public struct CompanionPerch: UIViewRepresentable {
    private let selection: Int
    private let slotCount: Int
    private let companionID: String
    private let isFocused: Bool
    private let bottomExtra: Double
    private let barScrub: BarScrubMode
    private let fingerSource: FingerSourceChoice
    private let actionLabel: String?
    private let onAction: (() -> Void)?
    private let onDragRelease: ((Int) -> Void)?
    private let onHaptic: ((HapticKind) -> Void)?
    private let onError: ((Error, String) -> Void)?

    /// `selection` is the index of the selected slot; a host whose tab tags are
    /// not indexes maps them. `isFocused` sets `isPerchFocused`. The others set
    /// the property of the same name on `CompanionPerchView`.
    public init(
        selection: Int,
        slotCount: Int,
        companionID: String = CompanionId.DEFAULT_COMPANION_ID,
        isFocused: Bool = true,
        bottomExtra: Double = 0,
        barScrub: BarScrubMode = .native,
        fingerSource: FingerSourceChoice = .nativeTabBar,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil,
        onDragRelease: ((Int) -> Void)? = nil,
        onHaptic: ((HapticKind) -> Void)? = nil,
        onError: ((Error, String) -> Void)? = nil
    ) {
        self.selection = selection
        self.slotCount = slotCount
        self.companionID = companionID
        self.isFocused = isFocused
        self.bottomExtra = bottomExtra
        self.barScrub = barScrub
        self.fingerSource = fingerSource
        self.actionLabel = actionLabel
        self.onAction = onAction
        self.onDragRelease = onDragRelease
        self.onHaptic = onHaptic
        self.onError = onError
    }

    /// Remembers the last finger source applied: it is not `Equatable`, and
    /// assigning one resets any drag in progress.
    @MainActor
    public final class Coordinator {
        fileprivate var appliedFingerSource: FingerSourceChoice = .nativeTabBar
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> CompanionPerchView {
        let view = CompanionPerchView(
            companionID: companionID,
            anchor: CompanionAnchor(slotCount: slotCount, slotIndex: selection),
            onError: onError
        )
        view.isPerchFocused = isFocused
        view.bottomExtra = bottomExtra
        view.barScrub = barScrub
        view.actionLabel = actionLabel
        view.onAction = onAction
        view.onDragRelease = onDragRelease
        view.onHaptic = onHaptic
        if !Self.isSame(fingerSource, context.coordinator.appliedFingerSource) {
            view.fingerSource = fingerSource
            context.coordinator.appliedFingerSource = fingerSource
        }
        return view
    }

    public func updateUIView(_ uiView: CompanionPerchView, context: Context) {
        if uiView.companionID != companionID {
            uiView.companionID = companionID
        }
        if uiView.anchor.slotCount != slotCount {
            uiView.anchor = CompanionAnchor(slotCount: slotCount, slotIndex: selection)
        } else if uiView.anchor.slotIndex != selection {
            uiView.selectTab(selection)
        }
        if uiView.isPerchFocused != isFocused {
            uiView.isPerchFocused = isFocused
        }
        if uiView.bottomExtra != bottomExtra {
            uiView.bottomExtra = bottomExtra
        }
        if uiView.barScrub != barScrub {
            uiView.barScrub = barScrub
        }
        if !Self.isSame(fingerSource, context.coordinator.appliedFingerSource) {
            uiView.fingerSource = fingerSource
            context.coordinator.appliedFingerSource = fingerSource
        }
        if uiView.actionLabel != actionLabel {
            uiView.actionLabel = actionLabel
        }
        uiView.onAction = onAction
        uiView.onDragRelease = onDragRelease
        uiView.onHaptic = onHaptic
        uiView.onError = onError
    }

    public static func dismantleUIView(_ uiView: CompanionPerchView, coordinator: Coordinator) {
        uiView.detach()
    }

    private static func isSame(_ lhs: FingerSourceChoice, _ rhs: FingerSourceChoice) -> Bool {
        switch (lhs, rhs) {
        case (.nativeTabBar, .nativeTabBar), (.none, .none): return true
        case (.custom(let a), .custom(let b)): return a === b
        default: return false
        }
    }
}
#endif
