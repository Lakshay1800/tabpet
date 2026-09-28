import UIKit
import TabPetUIKit

/// Five tabs, plus a companion perched above the bar. The delegate call is
/// the only thing this controller does for the perch: it never reaches into
/// the pushed or presented screens below.
final class RootTabBarController: UITabBarController, UITabBarControllerDelegate {
    let perch: CompanionPerchView

    init() {
        perch = CompanionPerchView(
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 0)
        )
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
        perch.attach(to: self)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else { return }
        perch.selectTab(index)
    }
}
