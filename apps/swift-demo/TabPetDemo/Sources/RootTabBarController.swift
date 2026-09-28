import UIKit

/// Five plain tabs. Nothing here reaches for a perch or a pet on the tab bar
/// itself - that arrives with later work.
final class RootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

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

        let controls = ControlsViewController()
        controls.tabBarItem = UITabBarItem(title: "Controls", image: UIImage(systemName: "slider.horizontal.3"), tag: 4)

        viewControllers = [overview, activity, notes, settings, controls].map {
            UINavigationController(rootViewController: $0)
        }
    }
}
