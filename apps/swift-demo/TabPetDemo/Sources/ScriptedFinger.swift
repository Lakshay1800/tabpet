import UIKit
import TabPetUIKit

/// Launch arguments for repeatable screen recordings: `-demoAnimal <id>`,
/// `-demoStartTab <0 to 4>`, `-demoBarScrub native|exclusive`,
/// `-scriptedDrag near|far|cancel`.
struct DemoLaunchOptions {
    enum Drag: String {
        case near
        case far
        case cancel
    }

    let animal: String?
    let startTab: Int?
    let barScrub: BarScrubMode?
    let drag: Drag?

    init(defaults: UserDefaults = .standard) {
        animal = defaults.string(forKey: "demoAnimal")
        startTab = defaults.string(forKey: "demoStartTab").flatMap(Int.init).flatMap { (0..<5).contains($0) ? $0 : nil }
        switch defaults.string(forKey: "demoBarScrub") {
        case "native": barScrub = .native
        case "exclusive": barScrub = .exclusive
        default: barScrub = nil
        }
        drag = defaults.string(forKey: "scriptedDrag").flatMap(Drag.init(rawValue:))
    }
}

/// A finger feed that plays one scripted drag at about 60 samples a second.
@MainActor
final class ScriptedFingerSource: FingerSource {
    private var listener: (@MainActor (PanEvent) -> Void)?
    private var timer: Timer?

    func subscribe(_ listener: @escaping @MainActor (PanEvent) -> Void) -> FingerSubscription {
        self.listener = listener
        return FingerSubscription { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.listener = nil
        }
    }

    /// Down at `from`, moves to `to` at `speed` pt per second, holds, then ends
    /// (or cancels). All x values are window space.
    func play(from: Double, to: Double, speed: Double = 200, holdSeconds: Double, cancel: Bool) {
        timer?.invalidate()
        let travel = abs(to - from) / speed
        let total = travel + holdSeconds
        let start = CACurrentMediaTime()
        listener?(PanEvent(x: from, phase: .began))
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            let elapsed = CACurrentMediaTime() - start
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if elapsed >= total {
                    timer.invalidate()
                    self.timer = nil
                    self.listener?(PanEvent(x: to, phase: cancel ? .cancelled : .ended))
                    return
                }
                if elapsed < travel {
                    let t = travel > 0 ? elapsed / travel : 1
                    self.listener?(PanEvent(x: from + (to - from) * t, phase: .moved))
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
