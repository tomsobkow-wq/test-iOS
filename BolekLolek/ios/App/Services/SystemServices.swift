import AgentCore
import Contacts
import CoreLocation
import AlarmKit
import EventKit
import Foundation
import UIKit
import UserNotifications
import WeatherKit

// Real iPhone implementations of the protocols the tools use.
// Each asks for its permission the first time it is needed, not at launch.

// MARK: - Notifications (alarms, timers, reminders)

struct LocalNotifications: NotificationScheduling {
    func schedule(_ notification: ScheduledNotification) async throws {
        // Alarms and timers ring like the Clock app where iOS allows it; everything else (and any failure) is a notification.
        if #available(iOS 26.0, *), notification.isAlarm, notification.repeats == nil {
            do {
                try await AlarmRinger.schedule(title: notification.title, at: notification.fireDate)
                #if DEBUG
                await NotificationDebug.dump(reason: "alarm scheduled for \(notification.fireDate)")
                #endif
                return
            } catch {
                #if DEBUG
                await NotificationDebug.dump(reason: "alarm failed (\(error)); using a notification")
                #endif
            }
        }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw ToolError("Notifications are turned off for this app. Enable them in Settings to use alarms and reminders.")
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        if let body = notification.body { content.body = body }
        // iOS limits notification sounds to 30 seconds; a true alarm clock needs AlarmKit (iOS 26+).
        content.sound = .default
        content.interruptionLevel = .active

        let calendar = Calendar.current
        let components: Set<Calendar.Component>
        switch notification.repeats {
        case nil: components = [.year, .month, .day, .hour, .minute, .second]
        case .daily: components = [.hour, .minute]
        case .weekly: components = [.weekday, .hour, .minute]
        case .monthly: components = [.day, .hour, .minute]
        case .yearly: components = [.month, .day, .hour, .minute]
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(components, from: notification.fireDate),
            repeats: notification.repeats != nil
        )
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        #if DEBUG
        await NotificationDebug.dump(reason: "scheduled for \(notification.fireDate)")
        #endif
    }
}

#if DEBUG
/// Debug only: writes the app's notification permission and what is pending or delivered (titles and counts, no other apps) to Documents/notifications.txt.
enum NotificationDebug {
    static func dump(reason: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        func name(_ s: UNNotificationSetting) -> String { s == .enabled ? "on" : (s == .disabled ? "off" : "n/a") }
        let status = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"][min(settings.authorizationStatus.rawValue, 4)]
        var alarms = ""
        if #available(iOS 26.0, *) { alarms = " alarmKit=\(AlarmManager.shared.authorizationState) alarms=\(((try? AlarmManager.shared.alarms) ?? []).map { String(describing: $0.state) })" }
        let line = "\(Date()) \(reason):\(alarms) auth=\(status) alert=\(name(settings.alertSetting)) sound=\(name(settings.soundSetting)) badge=\(name(settings.badgeSetting)) lock=\(name(settings.lockScreenSetting)) center=\(name(settings.notificationCenterSetting)) timeSensitive=\(name(settings.timeSensitiveSetting)) pending=\(pending.count) delivered=\(delivered.map(\.request.content.title))\n"
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent("notifications.txt")
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() } else { try? Data(line.utf8).write(to: url) }
    }
}
#endif

/// Lets notifications show as banners while the app is open too.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Calendar

final class EventKitCalendar: CalendarProviding, @unchecked Sendable {
    private let store = EKEventStore()

    private func authorize() async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw ToolError("Calendar access is turned off. Enable it in Settings to read or add events.")
        }
    }

    #if DEBUG
    /// Test helper: removes the events a test run created (titles starting "Lolek test").
    func removeTestEvents() async {
        guard (try? await store.requestFullAccessToEvents()) == true else { return }
        let from = Date().addingTimeInterval(-86400 * 30), to = Date().addingTimeInterval(86400 * 800)
        for event in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)) where event.title?.hasPrefix("Lolek test") == true {
            try? store.remove(event, span: .thisEvent)
        }
    }
    #endif

    func events(from: Date, to: Date) async throws -> [CalendarEventInfo] {
        try await authorize()
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEventInfo(title: $0.title ?? "Untitled", start: $0.startDate, end: $0.endDate, location: $0.location, isAllDay: $0.isAllDay)
        }
    }

    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> CalendarEventInfo {
        try await authorize()
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw ToolError("There is no calendar that accepts new events.")
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        try store.save(event, span: .thisEvent)
        return CalendarEventInfo(title: title, start: start, end: end, location: location)
    }
}

// MARK: - Contacts

final class SystemContacts: ContactsProviding, @unchecked Sendable {
    private let store = CNContactStore()

    func find(name: String) async throws -> [ContactInfo] {
        guard try await store.requestAccess(for: .contacts) else {
            throw ToolError("Contacts access is turned off. Enable it in Settings to look people up.")
        }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let store = self.store
        return try await Task.detached {
            try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
                .map { contact in
                    ContactInfo(
                        name: CNContactFormatter.string(from: contact, style: .fullName) ?? name,
                        phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue }
                    )
                }
        }.value
    }
}

// MARK: - Weather (WeatherKit)

/// Needs the WeatherKit capability on the App ID and a paid developer account.
/// Without it the call fails and the tool reports that plainly.
final class AppleWeather: WeatherProviding, @unchecked Sendable {
    func weather(for place: String?) async throws -> WeatherReport {
        let location: CLLocation
        let placeName: String
        if let place {
            guard let mark = try await CLGeocoder().geocodeAddressString(place).first, let found = mark.location else {
                throw ToolError("Could not find a place called \"\(place)\".")
            }
            location = found
            placeName = mark.locality ?? place
        } else {
            location = try await OneShotLocation().current()
            placeName = (try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality) ?? "Current location"
        }

        let weather: Weather
        do {
            weather = try await WeatherService.shared.weather(for: location)
        } catch {
            throw ToolError("Weather is unavailable (\(error.localizedDescription)). WeatherKit may not be enabled for this build.")
        }
        let today = weather.dailyForecast.first
        let nextRain = weather.hourlyForecast.first { $0.date > Date() && $0.precipitationChance >= 0.5 }
        var note: String?
        if let nextRain {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            note = "rain likely from \(formatter.string(from: nextRain.date))"
        }
        return WeatherReport(
            place: placeName,
            temperatureC: weather.currentWeather.temperature.converted(to: .celsius).value,
            feelsLikeC: weather.currentWeather.apparentTemperature.converted(to: .celsius).value,
            condition: weather.currentWeather.condition.description,
            highC: today?.highTemperature.converted(to: .celsius).value,
            lowC: today?.lowTemperature.converted(to: .celsius).value,
            precipitationChancePercent: today.map { Int(($0.precipitationChance * 100).rounded()) },
            note: note
        )
    }
}

/// The current position for weather: one location fix (asking permission the first time) and, if possible, the town's name.
enum SystemLocation {
    static func current() async throws -> (latitude: Double, longitude: Double, name: String?) {
        let location = try await OneShotLocation().current()
        let name = (try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality)
        return (location.coordinate.latitude, location.coordinate.longitude, name)
    }
}

/// One location fix, with the permission prompt on first use.
@MainActor
private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func current() async throws -> CLLocation {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(ToolError("Location access is turned off. Enable it in Settings, or tell me a city.")))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: finish(.failure(ToolError("Location access is turned off. Enable it in Settings, or tell me a city.")))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last { finish(.success(location)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
}

// MARK: - Opening Messages and the dialler

struct SystemURLOpener: URLOpening {
    func open(_ url: URL) async -> Bool {
        await MainActor.run {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return true
        }
    }
}
