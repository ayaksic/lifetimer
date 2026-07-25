import DeviceActivity
import ExtensionKit
import LifeTimerCore
import SwiftUI

@main
struct LifeTimerScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        LifeTimerScreenTimeReport()
    }
}
