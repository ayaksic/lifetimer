# Life Timer Watch Starter

This is a native SwiftUI starter for a stripped-down Apple Watch version of Life Timer.

It includes the six continuous flow views:

- Hour
- Today
- This Week
- This Month
- This Year
- Lifetime

Then it repeats those same six periods as segmented grid views:

- Hour: 60 minutes
- Today: 24 hours
- This Week: 168 hours
- This Month: calendar days
- This Year: 12 months
- Lifetime: 80 years

The lifetime start date defaults to April 17, 1985 at 3:41 AM.
The watch starter also follows the current web app behavior for:

- persisted lifetime start date/time
- long-pressing either Lifetime page to edit that date/time
- long-pressing the Hour flow page to toggle the lifetime unit-position line

## One-time Xcode setup

Your Mac has Xcode installed, but the command-line tools are currently selected instead of full Xcode. Open Xcode once first so it can finish installing components, then run this in Terminal:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

The second command should print an Xcode version instead of an `xcode-select` error.

## Create the watch app project

1. Open Xcode.
2. Choose `File` > `New` > `Project...`.
3. Choose the `watchOS` tab.
4. Pick `App`.
5. Use these settings:
   - Product Name: `Life Timer Watch`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Include Notification Scene: unchecked
   - Include Complication: unchecked for the first version
6. Save the project somewhere comfortable, for example next to this folder.

## Add this starter code

In the new Xcode project:

1. Open the generated app file, probably named `Life_Timer_WatchApp.swift`.
2. Replace its contents with `Sources/LifeTimerWatchApp.swift`.
3. Open `ContentView.swift`.
4. Replace its contents with `Sources/ContentView.swift`.
5. Add `Sources/LifeTimerCore.swift` to the watch app target.

## Run it

1. In Xcode's toolbar, choose an Apple Watch simulator as the run destination.
2. Press the Run button.
3. Use left/right swipes to move through the six flow views, then the six grid views.
4. Tap the screen once if the Digital Crown does not respond, then rotate the crown to move through the same twelve pages.

## First real-device run

After the simulator works, you can run it on your own Apple Watch from Xcode. You may need to enable Developer Mode on the watch/iPhone if Xcode asks for it.

This starter intentionally skips audio and complications. Those can be added once the basic app feels right on the wrist.
