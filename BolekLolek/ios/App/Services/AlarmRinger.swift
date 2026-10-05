import AgentCore
import AlarmKit
import SwiftUI
import UserNotifications

@available(iOS 26.0, *)
struct BolekAlarmMetadata: AlarmMetadata {}

/// Real alarms and timers (iOS 26 and later): they ring like the Clock app, through the silent switch and Focus.
/// An ordinary notification plays one short tone and stays quiet in silent mode, which is not what a timer is for.
/// Scheduled as a fixed-date alarm, so no countdown screen (and no extra widget) is needed.
@available(iOS 26.0, *)
enum AlarmRinger {
    static func schedule(title: String, at date: Date, isTimer: Bool = false) async throws {
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
        let id = UUID()
        _ = try await manager.schedule(id: id, configuration: configuration)
        AlarmLedger.record(.init(id: id.uuidString, title: title, fireDate: date, isTimer: isTimer, usesAlarmKit: true))
    }
}

/// What this app has scheduled and not yet rung. iOS does not list another app's alarms in the Clock app, so the app keeps
/// its own list (and shows it through the "list alarms" tool) and checks it against what iOS still has waiting.
enum AlarmLedger {
    struct Entry: Codable, Equatable {
        var id: String
        var title: String
        var fireDate: Date
        var isTimer: Bool
        var usesAlarmKit: Bool
    }

    private static let key = "alarmLedger"

    static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Entry]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    static func record(_ entry: Entry) { save(all() + [entry]) }
    static func remove(id: String) { save(all().filter { $0.id != id }) }
}

struct SystemAlarms: AlarmManaging {
    func pending() async -> [AlarmInfo] {
        var stillWaiting: [AlarmLedger.Entry] = []
        var iosAlarms = Set<String>()
        if #available(iOS 26.0, *) { iosAlarms = Set(((try? AlarmManager.shared.alarms) ?? []).map { $0.id.uuidString }) }
        let notifications = Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
        for entry in AlarmLedger.all() {
            let alive = entry.usesAlarmKit ? iosAlarms.contains(entry.id) : notifications.contains(entry.id)
            if alive, entry.fireDate > Date().addingTimeInterval(-30) { stillWaiting.append(entry) }
        }
        AlarmLedger.save(stillWaiting)
        return stillWaiting.map { AlarmInfo(id: $0.id, title: $0.title, fireDate: $0.fireDate, isTimer: $0.isTimer) }
    }

    func cancel(id: String) async throws {
        guard let entry = AlarmLedger.all().first(where: { $0.id == id }) else { throw ToolError("That alarm is not waiting any more.") }
        if entry.usesAlarmKit {
            if #available(iOS 26.0, *), let uuid = UUID(uuidString: id) { try? AlarmManager.shared.cancel(id: uuid) }
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
        AlarmLedger.remove(id: id)
    }
}
