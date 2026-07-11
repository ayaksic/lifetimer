# Life Timer iPhone + Live Activity Starter

This is a native SwiftUI starter for turning the current Life Timer web app into an iPhone app with an Hour Live Activity.

It ports the important behavior from `index.html`:

- Hour, Today, This Week, This Month, This Year, and Lifetime flow views
- The same six segmented grid views
- Swipe left/right to move through the twelve pages
- Long-press the Hour flow page to toggle the lifetime unit position line
- Long-press either Lifetime page to edit the life start date
- Double-tap to play `hope.mp3` when the sound file is included in the app bundle
- A native button to start or end the Hour Live Activity

The lifetime start defaults to April 17, 1985 at 3:41 AM.

## Live Activity shape

The Live Activity uses ActivityKit with a Widget Extension.

For the Hour timer, the app starts one activity with:

- `hourStart`: the current calendar hour start
- `hourEnd`: the next calendar hour start
- `staleDate`: the hour end

The Live Activity UI is date-driven. It uses SwiftUI timer/progress views so the Lock Screen and Dynamic Island can keep showing the current hour without the app trying to wake every second in the background.

That is the right first version for this app. Without a server/push flow, the activity can become stale at the end of the hour instead of automatically starting the next hour while the app is suspended. Starting the next hour automatically from the background is the next design decision, not something iOS will reliably let a normal app do on a per-hour schedule.

Apple references:

- ActivityKit overview: https://developer.apple.com/documentation/ActivityKit/
- Displaying live data with Live Activities: https://developer.apple.com/documentation/ActivityKit/displaying-live-data-with-live-activities
- ActivityConfiguration: https://developer.apple.com/documentation/widgetkit/activityconfiguration

## One-time Xcode setup

Your Mac currently has Xcode installed, but `xcodebuild` is pointed at the command-line tools. Open Xcode once so it can finish installing components, then run:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

The second command should print the Xcode version.

## Create the iPhone app project

1. Open Xcode.
2. Choose `File` > `New` > `Project...`.
3. Choose the `iOS` tab.
4. Pick `App`.
5. Use these settings:
   - Product Name: `Life Timer`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Minimum Deployments: iOS 17.0 or newer
6. Save the project wherever you want to keep the native app.

## Add these app files

In the generated app target:

1. Replace the generated app file with `Sources/LifeTimerApp.swift`.
2. Replace `ContentView.swift` with `Sources/ContentView.swift`.
3. Add `Sources/LiveActivityManager.swift`.
4. Add this repository as a local Swift package and link the `LifeTimerCore` product to the app target.
5. Add the repo's `hope.mp3` to the app target as a bundled resource if you want the double-tap sound.
6. Replace the generated `Assets.xcassets` with `Assets.xcassets` from this starter, or drag `Assets.xcassets/AppIcon.appiconset` into your existing asset catalog.

The included app icon uses the same `icon-1024.png` artwork as the web/PWA version.

## Add the Live Activity widget extension

1. In Xcode, choose `File` > `New` > `Target...`.
2. Choose `Widget Extension`.
3. Use Product Name: `Life Timer Widgets`.
4. Leave `Include Configuration Intent` unchecked.
5. Delete the generated widget files, or remove their target membership. The starter widget file already provides the widget extension's one `@main` entry point.
6. Add `Widgets/LifeTimerLiveActivityWidget.swift` to the widget extension target.
7. Link the same `LifeTimerCore` package product to the widget extension target too.

The package must be linked to both targets because both the app and widget extension use the exact same `LifeTimerHourAttributes` type.

Target membership matters:

- App target only: `LifeTimerApp.swift`, `ContentView.swift`, `LiveActivityManager.swift`, `hope.mp3`
- Widget extension target only: `LifeTimerLiveActivityWidget.swift`
- Both targets: `LifeTimerCore` package product

If Xcode reports that `@main` can only apply to one type in a module, one of the app files is accidentally included in the widget target or the widget file is accidentally included in the app target. Select the file, open the File Inspector, and fix the `Target Membership` checkboxes.

## Enable Live Activities

In the iOS app target's `Info.plist`, add:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

If your Xcode project uses generated Info.plists, add this under the iOS app target:

`Build Settings` > `Info.plist Values` > custom key `NSSupportsLiveActivities` = `YES`

You do not need push notifications for this first version because the app starts the Hour Live Activity locally.

## Run it

1. Choose an iPhone simulator or real iPhone running iOS 17+.
2. Run the `Life Timer` app target.
3. Tap `Start Hour Live Activity`.
4. Lock the simulator/device, or swipe home on a Dynamic Island device.
5. Use the app button again to end the activity.

Live Activities are best tested on a real iPhone. Simulator behavior is useful, but the Lock Screen and Dynamic Island presentations are not a perfect substitute for the device.
