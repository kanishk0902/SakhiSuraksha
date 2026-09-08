//
//  NotificationService.swift
//  Guardian
//
//  Calm, privacy-conscious local notifications. Content never reveals sensitive
//  detail on the lock screen beyond what the user needs.
//

import Foundation
import UserNotifications
import Observation

@Observable
final class NotificationService {

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Non-fatal — the app explains what remains available without it.
        }
        await refreshStatus()
    }

    enum Category {
        case checkIn, deviation, etaNearing, connectivity, meshDelivery, emergency, saferRoute

        var title: String {
            switch self {
            case .checkIn:      return "Safety check-in"
            case .deviation:    return "Route changed"
            case .etaNearing:   return "Almost there"
            case .connectivity: return "Connection update"
            case .meshDelivery: return "Alert relayed"
            case .emergency:    return "Emergency active"
            case .saferRoute:   return "Safer route available"
            }
        }
    }

    func notify(_ category: Category, body: String, after seconds: TimeInterval = 0.5) {
        let content = UNMutableNotificationContent()
        content.title = category.title
        content.body = body
        content.sound = category == .emergency ? .defaultCritical : .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(0.1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: trigger)
        center.add(request)
    }
}
