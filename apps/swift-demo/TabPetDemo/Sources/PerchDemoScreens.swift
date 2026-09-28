import UIKit
import TabPetUIKit

/// A pushed screen with its own perch on a transient slot, attached to the
/// same tab bar controller the push lives inside. Blurs the root perch
/// while it is up top, detaches its own on the way out.
final class PushedPerchViewController: UIViewController {
    private let perch: CompanionPerchView
    private weak var rootPerch: CompanionPerchView?
    private let label = UILabel()

    init(companionID: String, rootPerch: CompanionPerchView?) {
        perch = CompanionPerchView(
            companionID: companionID,
            anchor: CompanionAnchor(slotCount: 5, slotIndex: 4)
        )
        perch.transientSlot = true
        self.rootPerch = rootPerch
        super.init(nibName: nil, bundle: nil)
        title = "Pushed"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "A pushed screen with a transient slot."
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        perch.onError = { error, site in
            print("CompanionPerchView error at \(site): \(error)")
        }
        if let tabBarController {
            perch.attach(to: tabBarController)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rootPerch?.isPerchFocused = false
        perch.isPerchFocused = true
    }

    // No isMovingFromParent guard: a cancelled edge-swipe pop reverses
    // through a fresh viewWillAppear, and a tab switch away must blur this
    // pet and restore the root even though nothing is being popped.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        perch.isPerchFocused = false
        rootPerch?.isPerchFocused = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent else { return }
        perch.detach()
    }
}

/// A full screen modal with no tab bar of its own - a plain screen showing
/// the pet before and after presentation, not its own perch instance.
final class ModalDemoViewController: UIViewController {
    private let label = UILabel()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "A full screen modal, no tab bar of its own."
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        var configuration = UIButton.Configuration.bordered()
        configuration.title = "Close"
        closeButton.configuration = configuration
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, closeButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc
    private func close() {
        dismiss(animated: true)
    }
}
