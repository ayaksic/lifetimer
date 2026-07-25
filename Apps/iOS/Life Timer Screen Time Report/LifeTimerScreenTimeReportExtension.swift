import DeviceActivity
import ExtensionKit
import LifeTimerCore
import SwiftUI

@main
struct LifeTimerScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        LifeTimerScreenTimeReport(period: .hour, style: .flow)
        LifeTimerScreenTimeReport(period: .day, style: .flow)
        LifeTimerScreenTimeReport(period: .week, style: .flow)
        LifeTimerScreenTimeReport(period: .month, style: .flow)
        LifeTimerScreenTimeReport(period: .year, style: .flow)
        LifeTimerScreenTimeReport(period: .lifetime, style: .flow)
        LifeTimerScreenTimeReport(period: .hour, style: .grid)
        LifeTimerScreenTimeReport(period: .day, style: .grid)
        LifeTimerScreenTimeReport(period: .week, style: .grid)
        LifeTimerScreenTimeReport(period: .month, style: .grid)
        LifeTimerScreenTimeReport(period: .year, style: .grid)
        LifeTimerScreenTimeReport(period: .lifetime, style: .grid)
    }
}
