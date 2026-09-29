# Swift demo

A small iOS app that puts the animal on a tab bar, in UIKit and in SwiftUI. It depends on the Swift package at the repository root by a relative path, and registers all six animals at launch.

## What it shows

- Five tabs with a perch above the bar. Tap a tab and the animal runs to it. Drag along the bar and it chases the finger.
- The Controls tab: an animal picker, a bar scrub picker (`native` or `exclusive`), a busy switch that holds a busy claim, a raised seat switch (`bottomExtra`), and two `CompanionSpriteView`s with pose and facing controls.
- A pushed screen with its own perch on a transient slot, and a full screen modal.
- A button that swaps to the same five tabs in SwiftUI, with `CompanionPerch` over a `TabView`.

## Open and run

Needs Xcode 16 or later.

1. Open `TabPetDemo.xcodeproj` in Xcode.
2. Pick the `TabPetDemo` scheme and an iPhone simulator.
3. Run.

From a terminal, `tools/swift-demo-build.sh <simulator-udid>` at the repository root builds it for the simulator without signing. The udid comes from `xcrun simctl list devices`.

To run it on a phone, the project has signing turned off, so choose a team first: open the `TabPetDemo` target, Signing and Capabilities, and pick your team. Then choose the phone and run. Do not commit that change.

The finger chase is tuned for a finger, so check it on a device. For a recording that repeats, the scripted drag below feeds the perch its own finger events on a simulator.

## Launch arguments

Set them in the scheme under Run, Arguments Passed On Launch, or pass them on the command line:

```bash
xcrun simctl launch <simulator-udid> org.tabpet.demo -demoAnimal raccoon -demoStartTab 0
```

| argument | values | effect |
| --- | --- | --- |
| `-demoAnimal` | an animal id, such as `raccoon` | the animal at launch |
| `-demoStartTab` | `0` to `4` | the selected tab at launch |
| `-demoBarScrub` | `native` or `exclusive` | the perch's `barScrub` |
| `-scriptedDrag` | `near`, `far` or `cancel` | plays one scripted drag two seconds after the UIKit tabs appear |
| `-demoRoot` | `uikit` or `swiftui` | which of the two apps opens first |

## Changing the project

`project.yml` is the file to edit. The project is generated from it with [XcodeGen](https://github.com/yonaskolb/XcodeGen): run `xcodegen generate` in this directory. See `CONTRIBUTING.md` for the details.
