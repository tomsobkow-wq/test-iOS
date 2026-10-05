import AgentCore
import AlarmKit
import SwiftUI

@available(iOS 26.0, *)
struct BolekAlarmMetadata: AlarmMetadata {}

/// Real alarms and timers (iOS 26 and later): they ring like the Clock app, through the silent switch and Focus.
/// An ordinary notification plays one short tone and stays quiet in silent mode, which is not what a timer is for.
/// Scheduled as a fixed-date alarm, so no countdown screen (and no extra widget) is needed.
@available(iOS 26.0, *)
enum AlarmRinger {
    static func schedule(title: String, at date: Date) async throws {
        let manager = AlarmManager.shared
        var state = manager.authorizationState
        if state == .notDetermined { state = try await manager.requestAuthorization() }
        guard state == .authorized else {
            throw ToolError("Alarms are turned off for this app. Enable them in Settings so timers and alarms can ring.")
        }
        let stop = AlarmButton(text: "Done", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop)
        let attributes = AlarmAttributes<BolekAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert), metadata: nil, tintColor: Color(red: 0.110, green: 0.502, blue: 0.282)
        )
        let configuration = AlarmManager.AlarmConfiguration<BolekAlarmMetadata>.alarm(schedule: .fixed(date), attributes: attributes)
        _ = try await manager.schedule(id: UUID(), configuration: configuration)
    }
}
