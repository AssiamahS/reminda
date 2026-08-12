import Foundation
import CoreLocation
import UserNotifications
import Observation

@Observable
@MainActor
final class ReminderStore {
    var reminders: [Reminder] = []
    var nearbyIDs: Set<UUID> = []

    private let manager = CLLocationManager()
    private var locationTask: Task<Void, Never>?

    private let saveURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("reminders.json")

    init() {
        load()
        rescheduleAll()
    }

    // MARK: lifecycle

    func start() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
        manager.requestWhenInUseAuthorization()
        watchLocation()
    }

    private func watchLocation() {
        locationTask?.cancel()
        locationTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard !Task.isCancelled else { break }
                    if let location = update.location {
                        self.refreshNearby(location)
                    }
                }
            } catch {
                // no location permission — glow feature stays off
            }
        }
    }

    private func refreshNearby(_ location: CLLocation) {
        var near: Set<UUID> = []
        for reminder in reminders where reminder.hasPlace && !reminder.done {
            let target = CLLocation(latitude: reminder.latitude ?? 0, longitude: reminder.longitude ?? 0)
            if location.distance(from: target) < 800 {
                near.insert(reminder.id)
            }
        }
        if near != nearbyIDs {
            nearbyIDs = near
        }
    }

    // MARK: CRUD

    func add(_ reminder: Reminder) {
        reminders.insert(reminder, at: 0)
        schedule(reminder)
        save()
        if let place = reminder.place, !reminder.hasPlace {
            let id = reminder.id
            Task {
                if let mark = try? await CLGeocoder().geocodeAddressString(place).first,
                   let loc = mark.location {
                    self.setCoordinate(id: id, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                }
            }
        }
    }

    private func setCoordinate(id: UUID, lat: Double, lon: Double) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].latitude = lat
        reminders[index].longitude = lon
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].done.toggle()
        if reminders[index].done {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        } else {
            schedule(reminders[index])
        }
        save()
    }

    func delete(_ id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        reminders.removeAll { $0.id == id }
        save()
    }

    // MARK: notifications

    private func schedule(_ reminder: Reminder) {
        guard !reminder.done, let due = reminder.due, due > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let place = reminder.place {
            content.body = "at \(place)"
        }
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger))
    }

    private func rescheduleAll() {
        for reminder in reminders where !reminder.done {
            schedule(reminder)
        }
    }

    // MARK: persistence

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            try? data.write(to: saveURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = saved
    }
}
