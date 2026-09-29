import UIKit
import TabPetCore
import TabPetUIKit

/// Five tabs, plus a companion perched above the bar. The delegate call is
/// the only thing this controller does for the perch: it never reaches into
/// the pushed or presented screens below.
final class RootTabBarController: UITabBarController, UITabBarControllerDelegate {
    let perch: CompanionPerchView
    private let options = DemoLaunchOptions()
    private let scriptedSource = ScriptedFingerSource()
    private var didScheduleDrag = false

    init() {
        let options = DemoLaunchOptions()
        if let animal = options.animal, CompanionRegistry.shared.get(animal) != nil {
            perch = CompanionPerchView(
                companionID: animal,
                anchor: CompanionAnchor(slotCount: 5, slotIndex: options.startTab ?? 0)
            )
        } else {
            perch = CompanionPerchView(
                anchor: CompanionAnchor(slotCount: 5, slotIndex: options.startTab ?? 0)
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        let overview = ListViewController(title: "Overview", rows: [
            "Welcome", "What's new", "Getting started", "Status",
        ])
        overview.tabBarItem = UITabBarItem(title: "Overview", image: UIImage(systemName: "square.grid.2x2"), tag: 0)

        let activity = ListViewController(title: "Activity", rows: [
            "Today", "This week", "Earlier", "Archive",
        ])
        activity.tabBarItem = UITabBarItem(title: "Activity", image: UIImage(systemName: "list.bullet"), tag: 1)

        let notes = ListViewController(title: "Notes", rows: [
            "Draft", "Shared", "Starred", "Trash",
        ])
        notes.tabBarItem = UITabBarItem(title: "Notes", image: UIImage(systemName: "note.text"), tag: 2)

        let settings = ListViewController(title: "Settings", rows: [
            "Account", "Appearance", "Notifications", "About",
        ])
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 3)

        let controls = ControlsViewController(perch: perch)
        controls.tabBarItem = UITabBarItem(title: "Controls", image: UIImage(systemName: "slider.horizontal.3"), tag: 4)

        viewControllers = [overview, activity, notes, settings, controls].map {
            UINavigationController(rootViewController: $0)
        }

        perch.onError = { error, site in
            print("CompanionPerchView error at \(site): \(error)")
        }
        if let startTab = options.startTab {
            selectedIndex = startTab
        }
        if let barScrub = options.barScrub {
            perch.barScrub = barScrub
        }
        perch.onDragRelease = { [weak self] slot in
            guard let self, let count = self.viewControllers?.count, (0..<count).contains(slot) else { return }
            self.selectedIndex = slot
            self.perch.selectTab(slot)
        }
        if options.drag != nil {
            perch.fingerSource = .custom(scriptedSource)
        }
        perch.attach(to: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let drag = options.drag, !didScheduleDrag else { return }
        didScheduleDrag = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.runScriptedDrag(drag)
        }
    }

    private func runScriptedDrag(_ drag: DemoLaunchOptions.Drag) {
        guard let layout = TabBarMeasurer.measure(in: view.window), layout.centers.count == 5 else { return }
        let centers = layout.centers
        let home = selectedIndex
        switch drag {
        case .near, .cancel:
            let target = home + 2 < centers.count ? home + 2 : home - 2
            scriptedSource.play(from: centers[home], to: centers[target], holdSeconds: 0.6, cancel: drag == .cancel)
        case .far:
            let farthest = centers.indices.max { abs(centers[$0] - centers[home]) < abs(centers[$1] - centers[home]) } ?? home
            let toward: Double = centers[home] >= centers[farthest] ? 1 : -1
            scriptedSource.play(from: centers[farthest], to: centers[farthest] + 60 * toward, holdSeconds: 1.5, cancel: false)
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else { return }
        perch.selectTab(index)
    }
}
