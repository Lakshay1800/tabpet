import SwiftUI
import UIKit
import TabPetCore
import TabPetUIKit

/// Where the demo starts and how the two demos swap: both swap the
/// window's root view controller.
enum DemoRoot {
    static func showSwiftUI(in window: UIWindow?) {
        window?.rootViewController = UIHostingController(rootView: SwiftUIDemoScreen(options: DemoLaunchOptions()))
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    static func showUIKit(in window: UIWindow?) {
        window?.rootViewController = RootTabBarController()
    }
}

/// The same five tabs on a SwiftUI `TabView`, with the perch laid over it.
/// The last tab holds the animal picker, a tap counter and the way back.
struct SwiftUIDemoScreen: View {
    private static let tabs: [(title: String, icon: String, rows: [String])] = [
        ("Overview", "square.grid.2x2", ["Welcome", "What's new", "Getting started", "Status"]),
        ("Activity", "list.bullet", ["Today", "This week", "Earlier", "Archive"]),
        ("Notes", "note.text", ["Draft", "Shared", "Starred", "Trash"]),
        ("Settings", "gearshape", ["Account", "Appearance", "Notifications", "About"]),
    ]

    private let ids = CompanionRegistry.shared.ids()
    @State private var tab: Int
    @State private var animal: String
    @State private var taps = 0

    init(options: DemoLaunchOptions) {
        let ids = CompanionRegistry.shared.ids()
        _tab = State(initialValue: options.startTab ?? 0)
        let requested = options.animal.flatMap { ids.contains($0) ? $0 : nil }
        _animal = State(initialValue: requested ?? ids.first ?? CompanionId.DEFAULT_COMPANION_ID)
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, item in
                List(item.rows, id: \.self) { Text($0) }
                    .listStyle(.insetGrouped)
                    .tabItem { Label(item.title, systemImage: item.icon) }
                    .tag(index)
            }
            controls
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .overlay {
            CompanionPerch(
                selection: tab,
                slotCount: 5,
                companionID: animal,
                onAction: { taps += 1 },
                onError: { error, site in print("CompanionPerch error at \(site): \(error)") }
            )
            .ignoresSafeArea()
        }
    }

    private var controls: some View {
        Form {
            Picker("Animal", selection: $animal) {
                ForEach(ids, id: \.self) { Text($0).tag($0) }
            }
            Text("Pet taps: \(taps)")
            Button("Back to the UIKit demo") {
                DemoRoot.showUIKit(in: DemoRoot.keyWindow())
            }
        }
    }
}
