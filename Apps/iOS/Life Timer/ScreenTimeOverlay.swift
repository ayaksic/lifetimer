import Combine
import DeviceActivity
import FamilyControls
import Foundation
import LifeTimerCore
import SwiftUI

extension DeviceActivityReport.Context {
    static let lifeTimerScreenTime = Self("life-timer-screen-time")
}

@MainActor
final class ScreenTimeOverlay: ObservableObject {
    enum Status: Equatable {
        case off
        case ready
        case requesting
        case denied
        case unavailable(String)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: Status

    private static let enabledKey = "lifeTimer.screenTimeOverlay.enabled"
    private let authorizationCenter = AuthorizationCenter.shared
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let approved = Self.isApproved(authorizationCenter.authorizationStatus)
        let savedEnabled = defaults.bool(forKey: Self.enabledKey)
        let enabled = savedEnabled && approved
        isEnabled = enabled
        status = enabled ? .ready : (savedEnabled ? .denied : .off)
    }

    var statusLabel: String {
        switch status {
        case .off:
            "Off"
        case .ready:
            "Ready"
        case .requesting:
            "Requesting access"
        case .denied:
            "Screen Time access not granted"
        case .unavailable:
            "Unavailable"
        }
    }

    var statusDetail: String? {
        guard case let .unavailable(detail) = status else { return nil }
        return detail
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            isEnabled = false
            status = .off
            defaults.set(false, forKey: Self.enabledKey)
            return
        }

        status = .requesting

        do {
            if !Self.isApproved(authorizationCenter.authorizationStatus) {
                try await authorizationCenter.requestAuthorization(for: .individual)
            }

            guard Self.isApproved(authorizationCenter.authorizationStatus) else {
                isEnabled = false
                status = .denied
                defaults.set(false, forKey: Self.enabledKey)
                return
            }

            isEnabled = true
            status = .ready
            defaults.set(true, forKey: Self.enabledKey)
        } catch {
            isEnabled = false
            status = .unavailable(error.localizedDescription)
            defaults.set(false, forKey: Self.enabledKey)
        }
    }

    func refreshAuthorizationStatus() {
        guard isEnabled else { return }
        guard Self.isApproved(authorizationCenter.authorizationStatus) else {
            isEnabled = false
            status = .denied
            defaults.set(false, forKey: Self.enabledKey)
            return
        }
        status = .ready
    }

    func filter(
        for period: LifePeriod,
        now: Date,
        lifetimeStart: Date
    ) -> DeviceActivityFilter {
        let fullRange = period.range(containing: now, lifetimeStart: lifetimeStart)
        let end = min(now, fullRange.end)
        let range = DateInterval(
            start: min(fullRange.start, end.addingTimeInterval(-1)),
            end: end
        )

        let segment: DeviceActivityFilter.SegmentInterval
        switch period {
        case .hour, .day, .week, .month:
            segment = .hourly(during: range)
        case .year:
            segment = .daily(during: range)
        case .lifetime:
            segment = .weekly(during: range)
        }

        return DeviceActivityFilter(
            segment: segment,
            devices: .init([.iPhone])
        )
    }

    private static func isApproved(_ status: AuthorizationStatus) -> Bool {
        switch status {
        case .approved, .approvedWithDataAccess:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}
