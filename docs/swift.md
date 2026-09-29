# Swift guide

The same animal, for a native iOS app. No Expo and no React Native needed.

## What it is

A small animal that sits on your tab bar. It sits on the selected tab, runs to the next one when the tab changes, and chases a finger that drags along the bar. It comes as a Swift package with a UIKit view (`CompanionPerchView`) and a SwiftUI wrapper (`CompanionPerch`). There is also a plain sprite you can put anywhere in a screen (`CompanionSpriteView`, `CompanionSprite`).

## Requirements

- iOS 15.1 or later
- A toolchain with Swift 5.9 or later (the manifest says `swift-tools-version: 5.9`)
- The views are iOS only. On macOS the package builds and `swift test` runs, but only the core, motion and animal targets have anything in them: every file in `TabPetUIKit` sits behind `#if canImport(UIKit)`, so no view exists there. The `TabPetUIKit` tests run on an iOS simulator with `tools/swift-sim-test.sh`.

The perch finds the bar by the names of UIKit's private tab bar views, because no public API gives their frames. Those names were checked on iOS 26.5. If none of them are found, the perch falls back to the bar's `UIControl` descendants.

## Install

In Xcode, choose File, Add Package Dependencies, and enter the repository URL:

```
https://github.com/Lakshay1800/tabpet
```

Or add it to a `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.iOS("15.1")],
    dependencies: [
        .package(url: "https://github.com/Lakshay1800/tabpet", from: "X.Y.Z"),
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "TabPetUIKit", package: "tabpet"),
                .product(name: "TabPetCore", package: "tabpet"),
                .product(name: "TabPetAnimalPanda", package: "tabpet"),
            ]
        ),
    ]
)
```

`X.Y.Z` stands for the version you want. The first version that carries the Swift package is named in the [changelog](../CHANGELOG.md).

Products to add:

| product | what it holds |
| --- | --- |
| `TabPetUIKit` | the views: `CompanionPerchView`, `CompanionPerch`, `CompanionSpriteView`, `CompanionSprite` |
| `TabPetCore` | the registry, `CompanionProfile`, `CompanionState` and the value types. Add it when your code names them |
| `TabPetAnimalPanda`, `TabPetAnimalCat`, `TabPetAnimalTurtle`, `TabPetAnimalRaccoon`, `TabPetAnimalBird`, `TabPetAnimalSquirrel` | one animal each, with its sheets |
| `TabPetAnimals` | all six animals |

`TabPetMotion` is also a product. It is the engine under the views, and a host does not need it.

## One animal, not six

Each animal is its own product with its own three sprite sheets. A target that depends on one animal product ships that animal's art and no other. `TabPetAnimals` depends on all six, so add it only if you want all six. `tools/swift-isolation-check.sh` checks in CI that no animal target reaches another one.

The sheets on disk, in kilobytes (1 kB is 1000 bytes):

| animal   | idle | run | sit  | all three |
| -------- | ---- | --- | ---- | --------- |
| panda    | 1306 | 510 | 1247 | 3063      |
| cat      | 992  | 536 | 956  | 2483      |
| turtle   | 620  | 331 | 480  | 1431      |
| raccoon  | 823  | 366 | 659  | 1848      |
| bird     | 848  | 316 | 558  | 1722      |
| squirrel | 1003 | 477 | 997  | 2477      |

All six together are about 13 MB.

## Register the animals

The registry is empty until you fill it. Register once, before any view is created. `application(_:didFinishLaunchingWithOptions:)` is the usual place.

```swift
import UIKit
import TabPetAnimalCat
import TabPetAnimalPanda

final class AppDelegateExample: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        TabPetAnimalPanda.register()
        TabPetAnimalCat.register()
        return true
    }
}
```

With the umbrella product it is one call:

```swift
import TabPetAnimals

@MainActor
func registerEverything() {
    TabPetAnimals.registerAll()
}
```

Every `register` call goes into `CompanionRegistry.shared` unless you pass another registry as `register(in:)`.

A view asks for an animal by id (`"panda"`, `"cat"`, `"turtle"`, `"raccoon"`, `"bird"`, `"squirrel"`). If that id is not registered, the view uses the default id, `"panda"`. If that is not registered either, it uses the first animal that is. If nothing is registered, it draws nothing and reports `noProfileRegistered` through `onError`. It never crashes.

## UIKit

A tab bar controller that creates the perch, attaches it, and tells it which tab is selected.

```swift
import UIKit
import TabPetUIKit

final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let perch: CompanionPerchView

    init() {
        perch = CompanionPerchView(
            companionID: "panda",
            anchor: CompanionAnchor(slotCount: 3, slotIndex: 0)
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

        let titles = ["Home", "Explore", "Settings"]
        viewControllers = titles.enumerated().map { index, title in
            let screen = UIViewController()
            screen.view.backgroundColor = .systemBackground
            screen.tabBarItem = UITabBarItem(title: title, image: nil, tag: index)
            return screen
        }

        perch.onError = { error, site in
            print("tabpet error at \(site): \(error)")
        }
        perch.attach(to: self)
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else { return }
        perch.selectTab(index)
    }
}
```

The library never sets your tab bar controller's delegate. You forward the selected tab yourself. `selectedIndex = n` in code does not call the delegate, so call `perch.selectTab(n)` beside it.

`attach(to:)` adds the perch above the tab bar controller's view, pinned to its bounds. Touches pass through it except on the animal. To remove it, call `detach()`. That also tears down its motion for good, so make a new view to bring the animal back.

## SwiftUI

A `TabView` with the overlay on top. The perch reads the tab bar from the window, so it needs no reference to it.

```swift
import SwiftUI
import TabPetAnimalPanda
import TabPetUIKit

@main
struct ContentApp: App {
    init() {
        TabPetAnimalPanda.register()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Text("Home").tabItem { Label("Home", systemImage: "house") }.tag(0)
            Text("Explore").tabItem { Label("Explore", systemImage: "safari") }.tag(1)
            Text("Settings").tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .overlay {
            CompanionPerch(selection: tab, slotCount: 3)
                .ignoresSafeArea()
        }
    }
}
```

`selection` is the index of the selected slot, counted from zero, left to right. If your tab tags are not indexes, map them before you pass one in.

## The perch, property by property

`CompanionPerchView` is created with `init(companionID:registry:anchor:handoff:busy:onError:)`. Only `anchor` is required.

| name | type | default | what it does |
| --- | --- | --- | --- |
| `companionID` | `String` | `"panda"` | The animal. Settable later; the perch loads the new sheets. Falls back as described under "Register the animals" |
| `registry` (init only) | `CompanionRegistry` | `.shared` | Where the animal is looked up |
| `anchor` | `CompanionAnchor` | required | The bar as the perch sees it. See below |
| `handoff` (init only) | `PerchHandoffStore` | a new store per perch | Where the perch remembers the last tab, x and seat height, so the next run starts where the last one ended. Pass one store to two perches to share it |
| `busy` (init only) | `CompanionState` | `.shared` | The busy claims the perch follows. See "Busy" |
| `onError` (init parameter and property) | `((Error, String) -> Void)?` | `nil` | Reports a refused value or a sheet that did not load, with a site string such as `"CompanionPerchView.anchor"`. It never throws |
| `isPerchFocused` | `Bool` | `true` | Set it to `false` while another screen covers the bar. The perch stops its motion and ignores the finger until it is `true` again. It also blurs itself when it leaves the window. Named so it does not collide with `UIView.isFocused` |
| `transientSlot` | `Bool` | `false` | For a pushed screen with its own perch: the animal snaps to `anchor.slotIndex` with no chase and never reads or writes the handoff store |
| `bottomExtra` | `Double` | `0` | Raises the seat by this many points. A value that is not finite is refused and reported as `invalidNumber` |
| `barScrub` | `BarScrubMode` | `.native` | `.native`: the bar's own scrub runs. `.exclusive`: the bar's scrub is held back and the host selects the tab in `onDragRelease`. Applies live |
| `onDragRelease` | `((Int) -> Void)?` | `nil` | Called once with the slot when a drag ends over another slot in `.exclusive` mode. Never for a cancelled drag |
| `fingerSource` | `FingerSourceChoice` | `.nativeTabBar` | Where finger samples come from. Changing it drops a drag in progress |
| `onAction` | `(() -> Void)?` | `nil` | Called when the animal is tapped, or activated with VoiceOver |
| `actionLabel` | `String?` | `nil` | The accessibility label of the animal. When `nil` it reads "Your companion {label}. Tap to say hi." |
| `onHaptic` | `((HapticKind) -> Void)?` | `nil` | Called with `.selection` when the animal is tapped. The view never plays a haptic itself |
| `attach(to:)` | method |  | Adds the view above a `UITabBarController`'s view |
| `detach()` | method |  | Removes the view and tears its motion down. Safe to call twice |
| `selectTab(_:)` | method |  | Sets `anchor.slotIndex` and brings the view to the front. A tap on the tab that is already selected only brings it to the front |

`CompanionAnchor` has `slotCount` and `slotIndex`, and three optional numbers for a bar the perch cannot measure: `slotCenters` (window-space x of each slot), `barTop` (window-space y of the bar's top edge) and `pill` (a `PillFrame`). Leave those three `nil` on a real `UITabBar` and the perch measures the bar. A `slotCount` below 1 is raised to 1 and reported as `invalidSlotCount`. A number that is not finite is dropped and reported as `invalidNumber`. The report fires when the anchor turns invalid, not on every later change.

`CompanionPerch`, the SwiftUI form, takes the same things as parameters:

| `CompanionPerch` parameter | default         | maps to                                  |
| -------------------------- | --------------- | ---------------------------------------- |
| `selection`                | required        | `anchor.slotIndex` (through `selectTab`) |
| `slotCount`                | required        | `anchor.slotCount`                       |
| `companionID`              | `"panda"`       | `companionID`                            |
| `isFocused`                | `true`          | `isPerchFocused`                         |
| `bottomExtra`              | `0`             | `bottomExtra`                            |
| `barScrub`                 | `.native`       | `barScrub`                               |
| `fingerSource`             | `.nativeTabBar` | `fingerSource`                           |
| `actionLabel`              | `nil`           | `actionLabel`                            |
| `onAction`                 | `nil`           | `onAction`                               |
| `onDragRelease`            | `nil`           | `onDragRelease`                          |
| `onHaptic`                 | `nil`           | `onHaptic`                               |
| `onError`                  | `nil`           | `onError`                                |

The wrapper has no parameter for `transientSlot`, `handoff`, `busy`, `registry`, or the optional anchor numbers. It always uses `.shared` for the registry and busy state. A pushed screen with its own perch is a UIKit job.

## Dragging along the bar

Drag a finger along the bar and the animal follows, a little behind. Three settings decide who does what.

- `barScrub`. On `.native`, the bar's own scrub keeps working: on the iOS 26 floating bar the pill follows the finger and the bar selects the tab on release. The animal chases alongside. On `.exclusive`, the bar's own recognizers wait for the perch's pan to fail and the touch is cancelled once the pan is recognized, so the bar's scrub does not run. The perch reports the released slot through `onDragRelease` and the host selects it.
- `onDragRelease`. Called once, with the slot the finger was released over, only for an ended drag in `.exclusive` mode, and only when that slot is not the current one. It is called after the perch has recorded the release, so you may select the tab inside the callback. If you do not select one within about 0.8 seconds, the animal walks back to its seat.
- `fingerSource`. `.nativeTabBar` adds a pan recognizer to the tab bar. `.none` gives no finger events at all. `.custom(source)` takes a feed you write, for a bar the library cannot attach to.

When a host needs `.exclusive`: when your app has to decide whether a tab may be selected (a locked tab, a confirm step), or when you show your own selection state and need to be the only thing that changes it. Pair it with `onDragRelease`:

```swift
import UIKit
import TabPetUIKit

@MainActor
func takeOverTheScrub(perch: CompanionPerchView, tabBarController: UITabBarController) {
    perch.barScrub = .exclusive
    perch.onDragRelease = { [weak tabBarController, weak perch] slot in
        guard let tabBarController, let perch else { return }
        guard (0..<(tabBarController.viewControllers?.count ?? 0)).contains(slot) else { return }
        tabBarController.selectedIndex = slot
        perch.selectTab(slot)
    }
}
```

When a host needs `.custom`: when the tab bar is not a `UITabBar`. A `FingerSource` delivers `PanEvent` values (window-space `x` and a phase of `.began`, `.moved`, `.ended` or `.cancelled`). Set `anchor.slotCenters`, `anchor.barTop` and, if the bar has one, `anchor.pill`, so the perch knows the bar.

```swift
import TabPetUIKit

@MainActor
final class MyBarFingerSource: FingerSource {
    private var listener: (@MainActor (PanEvent) -> Void)?

    func subscribe(_ listener: @escaping @MainActor (PanEvent) -> Void) -> FingerSubscription {
        self.listener = listener
        return FingerSubscription { [weak self] in self?.listener = nil }
    }

    func fingerDown(atX x: Double) { listener?(PanEvent(x: x, phase: .began)) }
    func fingerMoved(toX x: Double) { listener?(PanEvent(x: x, phase: .moved)) }
    func fingerUp(atX x: Double) { listener?(PanEvent(x: x, phase: .ended)) }
}

@MainActor
func useCustomBar(perch: CompanionPerchView, source: MyBarFingerSource) {
    perch.anchor = CompanionAnchor(
        slotCount: 4,
        slotIndex: 0,
        slotCenters: [60, 160, 260, 360],
        barTop: 780
    )
    perch.fingerSource = .custom(source)
}
```

Finger events are ignored while Reduce Motion is on, while `isPerchFocused` is `false`, and on a `transientSlot` perch. The chase is tuned for a finger, so check it on a device.

## The sprite alone

`CompanionSpriteView` is the animal without the bar: a `size` by `size` square that shows one pose. Set `pose` (`.idle`, `.run` or `.sit`), `facing` (`.left` or `.right`) and `isBusy`.

```swift
import UIKit
import TabPetUIKit

@MainActor
func makeSprite() -> CompanionSpriteView {
    let sprite = CompanionSpriteView(companionID: "cat", size: 88)
    sprite.pose = .sit
    sprite.facing = .left
    sprite.onPress = { print("tapped") }
    sprite.onSitDone = { print("settled") }
    return sprite
}
```

`size` defaults to 88. A size that is not finite or not above zero falls back to 88 and is reported as `invalidSize`. `pressAccessibilityLabel` sets the label a tap announces, and `onHaptic` reports `.selection` on a tap. The view owns its own display link and stops it when it leaves the window.

`CompanionSprite` is the same view for SwiftUI:

```swift
import SwiftUI
import TabPetCore
import TabPetUIKit

struct PetRow: View {
    @State private var taps = 0

    var body: some View {
        HStack {
            CompanionSprite(companionID: "cat", pose: .idle, facing: .right, size: 64, onPress: { taps += 1 })
            Text("Taps: \(taps)")
        }
    }
}
```

Its parameters are `companionID` (`"panda"`), `pose` (`.idle`), `busy` (`false`), `facing` (`.right`), `size` (`88`), `pressLabel`, `onPress`, `onSitDone`, `onHaptic` and `onError`. `PupPose` and `Facing` live in `TabPetCore`.

## Busy

A host holds a busy claim while it works, and the animal stands up and fidgets until the last claim is released.

```swift
import TabPetCore

@MainActor
func syncWhileThePetWatches() async {
    let release = CompanionState.shared.beginCompanionBusy()
    defer { release() }
    try? await Task.sleep(nanoseconds: 2_000_000_000)
}
```

What the code does with it:

- Claims are counted. The animal reacts only when the count goes from zero to one and back to zero, so two overlapping operations hold it busy until both finish.
- `release` can be called more than once; only the first call counts.
- While a claim is held, the resting pose is the idle loop, played slowly, in place of the sit pose. When the last claim goes, it sits again.
- A busy claim never interrupts a run or a drag. The animal finishes the move and then shows the busy pose.
- With Reduce Motion on, the fidget does not play.
- A perch follows `CompanionState.shared` by default. Pass `busy:` to `CompanionPerchView.init` to follow another instance. `CompanionPerch` always follows the shared one. A sprite takes its state directly, through `isBusy`.
- A perch starts listening the first time it enters a window. A claim taken before that still counts: the perch reads the current state when it starts.

## Your own animal

A custom animal is a `CompanionProfile` registered by id, the same as the shipped six.

```swift
import Foundation
import TabPetCore

@MainActor
func registerOtter() {
    guard
        let idle = Bundle.main.url(forResource: "otter-idle-sprite", withExtension: "png"),
        let run = Bundle.main.url(forResource: "otter-run-sprite", withExtension: "png"),
        let sit = Bundle.main.url(forResource: "otter-sit-sprite", withExtension: "png")
    else { return }

    let otter = CompanionProfile(
        id: "otter",
        label: "otter",
        runFps: 24,
        commitSpring: SpringConfig(duration: 400, dampingRatio: 0.8),
        trackSpring: SpringConfig(duration: 240, dampingRatio: 0.86),
        catchSpring: SpringConfig(duration: 260, dampingRatio: 0.9),
        hopHeight: -8,
        flightLift: 0,
        scale: 1,
        aroundRoute: false,
        footPad: 6.5,
        sheets: CompanionSheets(idle: idle, run: run, sit: sit)
    )
    CompanionRegistry.shared.register(otter)
}
```

Registering an id that already exists replaces that profile and keeps its place in `CompanionRegistry.shared.ids()`.

To load, each sheet must meet what `SpriteSheetCache` checks:

- The URL is a file URL. Any other URL is refused.
- The file decodes as an image.
- It is no more than 4096 pixels on a side.
- Its width and height divide evenly by the grid: the idle sheet is 5 columns by 5 rows, the run sheet is 4 by 3, and the sit sheet is 5 by 5 unless the profile sets `sitSheet`.

The shipped sheets use 240 pixel cells, so idle and sit are 1200 by 1200 and run is 960 by 720. The code checks the division, not the cell size. If any one of the three sheets fails, the view draws nothing and reports the failure through `onError` with a site such as `"CompanionSpriteView.loadSheet.run"`. A profile with `sheets` set to `nil` reports `noProfileRegistered` from the perch and `sheetUnavailable` from the sprite view.

Fields left out of the initializer take defaults: `headPad` 0, `footPad` 11, `seatLift` 6, `runSpeed` 340, and `sitSheet` 5 by 5, 25 frames at 12 fps. Making the sheets and measuring these numbers is covered in the [art pipeline](art-pipeline.md), and every field is described in the [profile reference](profiles.md).

## Accessibility and Reduce Motion

- The animal is one accessibility element with the button trait. Its label is "Your companion {label}. Tap to say hi." unless you set `actionLabel` (perch) or `pressAccessibilityLabel` (sprite). VoiceOver's activate gesture does the same as a tap: it calls `onHaptic(.selection)` and `onAction`.
- With no animal resolved, the element is not an accessibility element and takes no press.
- Reduce Motion is read from `UIAccessibility.isReduceMotionEnabled` and re-read when the setting changes.
- With Reduce Motion on: a tab change moves the animal to the new seat at once and it sits, with no run; pose changes cut instead of dissolving; the greeting on launch and on tap does not play; the press scale does not play; the busy fidget does not play; the flight lift snaps; the route around the pill is not taken; finger events are ignored.

## Art license

The art is CC BY 4.0. Give credit "tabpet, CC BY 4.0" in your app or repository. The text is in each animal target, in `LICENSE-ART.md`, and the same file is bundled with the product.

Each animal enum carries the credit line and the full text:

```swift
import TabPetAnimalSquirrel

let credit = TabPetAnimalSquirrel.attribution
let fullText = TabPetAnimalSquirrel.licenseText
```

`attribution` is `"tabpet, CC BY 4.0"` for the panda, cat, turtle, raccoon and bird, in `TabPetAnimalPanda`, `TabPetAnimalCat`, `TabPetAnimalTurtle`, `TabPetAnimalRaccoon` and `TabPetAnimalBird`. For the squirrel it is `"tabpet, CC BY 4.0. Created with Grok"`, and if you redistribute the squirrel sheets, keep "Created with Grok" next to the tabpet credit. `licenseText` is an empty string if the bundled file cannot be read.

## Differences from the React Native package

|  | React Native | Swift |
| --- | --- | --- |
| Selected tab | A prop, `anchor.slotIndex`, passed on every render | You call `selectTab(_:)` from your tab bar controller's delegate, or pass `selection` in SwiftUI. The library never sets the tab bar controller's delegate |
| Animals | `react-native-tabpet` registers all six. `react-native-tabpet/bare` registers none | Nothing is registered until you call `register()` on the animals you link. One product per animal, `TabPetAnimals` for all six |
| Raised seat | The route around the pill is refused only while the animal climbs to a raised seat | An animal whose seat is raised (`bottomExtra` above zero) never takes the route around the pill, because the path is planned against the pill and the animal is drawn higher |
| `onDragRelease` | Called before the release is settled | Called after the release is settled, so a host may select the tab inside the callback |
| Handoff store | One store for the whole app | Each perch has its own, unless you pass a shared `PerchHandoffStore` |
| Motion | Reanimated worklets and Expo modules | No Expo, no Reanimated, no JavaScript. The motion for one perch, the animal and its sprite, runs on one `CADisplayLink` |
| `onHaptic` | `'selection'` or `'impact'` | `HapticKind` has `.selection` and `.impact`, but the views send only `.selection` |

## The demo app

`apps/swift-demo` holds one app with five tabs and a perch, in UIKit. Its last tab has an animal picker, a bar scrub picker, a busy switch, a raised seat switch, two sprite views, a push with its own perch on a transient slot, a full screen modal, and a button that swaps to the same five tabs in SwiftUI. Open `apps/swift-demo/TabPetDemo.xcodeproj` in Xcode 16 or later, choose an iPhone simulator, and run. From a terminal, `tools/swift-demo-build.sh <simulator-udid>` builds it for the simulator.

It takes launch arguments, set in the scheme or on `xcrun simctl launch`:

| argument        | values                          |
| --------------- | ------------------------------- |
| `-demoAnimal`   | an animal id, such as `raccoon` |
| `-demoStartTab` | `0` to `4`                      |
| `-demoBarScrub` | `native` or `exclusive`         |
| `-scriptedDrag` | `near`, `far` or `cancel`       |
| `-demoRoot`     | `uikit` or `swiftui`            |

More in [apps/swift-demo/README.md](../apps/swift-demo/README.md).
