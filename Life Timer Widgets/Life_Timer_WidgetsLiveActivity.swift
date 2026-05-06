//
//  Life_Timer_WidgetsLiveActivity.swift
//  Life Timer Widgets
//
//  Created by Andrew Yaksic on 5/5/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Life_Timer_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Life_Timer_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Life_Timer_WidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Life_Timer_WidgetsAttributes {
    fileprivate static var preview: Life_Timer_WidgetsAttributes {
        Life_Timer_WidgetsAttributes(name: "World")
    }
}

extension Life_Timer_WidgetsAttributes.ContentState {
    fileprivate static var smiley: Life_Timer_WidgetsAttributes.ContentState {
        Life_Timer_WidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Life_Timer_WidgetsAttributes.ContentState {
         Life_Timer_WidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Life_Timer_WidgetsAttributes.preview) {
   Life_Timer_WidgetsLiveActivity()
} contentStates: {
    Life_Timer_WidgetsAttributes.ContentState.smiley
    Life_Timer_WidgetsAttributes.ContentState.starEyes
}
