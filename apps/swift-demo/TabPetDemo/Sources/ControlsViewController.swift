import UIKit
import TabPetCore
import TabPetUIKit

/// The gallery: an animal picker, a busy switch, two `CompanionSpriteView`s
/// at 88pt and 54pt, plus the same picker driving the tab bar perch, a
/// bottomExtra switch, a push with a transient slot, and a full screen modal.
final class ControlsViewController: UIViewController {
    private let ids = CompanionRegistry.shared.ids()
    private var selectedID: String
    private var pose: PupPose = .idle
    private var facing: Facing = .right
    private var isBusy = false
    private var busyRelease: (() -> Void)?

    private let perch: CompanionPerchView
    private let picker = UISegmentedControl()
    private let scrubPicker = UISegmentedControl(items: ["Native", "Exclusive"])
    private let busySwitch = UISwitch()
    private let raisedSwitch = UISwitch()
    private let largeSprite: CompanionSpriteView
    private let smallSprite: CompanionSpriteView
    private let largeSizeLabel = UILabel()
    private let smallSizeLabel = UILabel()

    init(perch: CompanionPerchView) {
        let ids = CompanionRegistry.shared.ids()
        selectedID = ids.first ?? CompanionId.DEFAULT_COMPANION_ID
        self.perch = perch
        largeSprite = CompanionSpriteView(companionID: selectedID, size: 88)
        smallSprite = CompanionSpriteView(companionID: selectedID, size: 54)
        super.init(nibName: nil, bundle: nil)
        title = "Controls"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        for view in [largeSprite, smallSprite] {
            view.onError = { error, site in
                // demo app: surface a load/render problem in the console only
                print("CompanionSpriteView error at \(site): \(error)")
            }
        }

        picker.removeAllSegments()
        for (index, id) in ids.enumerated() {
            picker.insertSegment(withTitle: id, at: index, animated: false)
        }
        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(animalChanged), for: .valueChanged)

        scrubPicker.selectedSegmentIndex = perch.barScrub == .exclusive ? 1 : 0
        scrubPicker.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)

        busySwitch.addTarget(self, action: #selector(busyChanged), for: .valueChanged)
        raisedSwitch.addTarget(self, action: #selector(raisedChanged), for: .valueChanged)

        largeSizeLabel.text = "88 pt"
        largeSizeLabel.font = .preferredFont(forTextStyle: .caption1)
        largeSizeLabel.textColor = .secondaryLabel
        smallSizeLabel.text = "54 pt"
        smallSizeLabel.font = .preferredFont(forTextStyle: .caption1)
        smallSizeLabel.textColor = .secondaryLabel

        buildLayout()
        applyState()
    }

    private func buildLayout() {
        let animalRow = labeledRow(label: "Animal", control: picker)
        let scrubRow = labeledRow(label: "Bar scrub", control: scrubPicker)
        let busyRow = labeledRow(label: "Busy", control: busySwitch)
        let raisedRow = labeledRow(label: "Raised seat", control: raisedSwitch)

        let largeColumn = UIStackView(arrangedSubviews: [largeSprite, largeSizeLabel])
        largeColumn.axis = .vertical
        largeColumn.alignment = .center
        largeColumn.spacing = 6

        let smallColumn = UIStackView(arrangedSubviews: [smallSprite, smallSizeLabel])
        smallColumn.axis = .vertical
        smallColumn.alignment = .center
        smallColumn.spacing = 6

        let gallery = UIStackView(arrangedSubviews: [largeColumn, smallColumn])
        gallery.axis = .horizontal
        gallery.alignment = .center
        gallery.distribution = .equalSpacing
        gallery.spacing = 32

        let idleButton = makeButton(title: "Idle", action: #selector(setIdle))
        let runButton = makeButton(title: "Run", action: #selector(setRun))
        let sitButton = makeButton(title: "Sit", action: #selector(setSit))
        let poseRow = UIStackView(arrangedSubviews: [idleButton, runButton, sitButton])
        poseRow.axis = .horizontal
        poseRow.distribution = .fillEqually
        poseRow.spacing = 12

        let flipButton = makeButton(title: "Flip facing", action: #selector(flipFacing))
        let pushButton = makeButton(title: "Push a transient perch", action: #selector(pushTransient))
        let modalButton = makeButton(title: "Present a full screen modal", action: #selector(presentModal))
        let swiftUIButton = makeButton(title: "Switch to the SwiftUI demo", action: #selector(switchToSwiftUI))

        let stack = UIStackView(arrangedSubviews: [
            animalRow, scrubRow, busyRow, raisedRow, gallery, poseRow, flipButton, pushButton, modalButton, swiftUIButton,
        ])
        stack.axis = .vertical
        stack.spacing = 24
        stack.setCustomSpacing(32, after: raisedRow)
        stack.setCustomSpacing(32, after: gallery)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func labeledRow(label text: String, control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .center
        return row
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc
    private func animalChanged() {
        guard picker.selectedSegmentIndex >= 0, picker.selectedSegmentIndex < ids.count else { return }
        selectedID = ids[picker.selectedSegmentIndex]
        largeSprite.companionID = selectedID
        smallSprite.companionID = selectedID
        perch.companionID = selectedID
    }

    @objc
    private func scrubChanged() {
        perch.barScrub = scrubPicker.selectedSegmentIndex == 1 ? .exclusive : .native
    }

    @objc
    private func busyChanged() {
        isBusy = busySwitch.isOn
        if isBusy {
            busyRelease = CompanionState.shared.beginCompanionBusy()
        } else {
            busyRelease?()
            busyRelease = nil
        }
        applyState()
    }

    @objc
    private func raisedChanged() {
        perch.bottomExtra = raisedSwitch.isOn ? 24 : 0
    }

    @objc
    private func pushTransient() {
        let pushed = PushedPerchViewController(companionID: selectedID, rootPerch: perch)
        navigationController?.pushViewController(pushed, animated: true)
    }

    @objc
    private func switchToSwiftUI() {
        DemoRoot.showSwiftUI(in: view.window)
    }

    @objc
    private func presentModal() {
        let modal = ModalDemoViewController()
        modal.modalPresentationStyle = .fullScreen
        present(modal, animated: true)
    }

    @objc
    private func setIdle() {
        pose = .idle
        applyState()
    }

    @objc
    private func setRun() {
        pose = .run
        applyState()
    }

    @objc
    private func setSit() {
        pose = .sit
        applyState()
    }

    @objc
    private func flipFacing() {
        facing = facing == .right ? .left : .right
        applyState()
    }

    private func applyState() {
        for view in [largeSprite, smallSprite] {
            view.pose = pose
            view.isBusy = isBusy
            view.facing = facing
        }
    }
}
