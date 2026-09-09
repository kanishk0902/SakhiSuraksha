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
        case guardianRequest, guardianAccepted, guardianAssisting

        var title: String {
            switch self {
            case .checkIn:      return "Safety check-in"
            case .deviation:    return "Route changed"
            case .etaNearing:   return "Almost there"
            case .connectivity: return "Connection update"
            case .meshDelivery: return "Alert relayed"
            case .emergency:    return "Emergency active"
            case .saferRoute:   return "Safer route available"
            case .guardianRequest:   return "Community Guardian request"
            case .guardianAccepted:  return "Community Guardian responding"
            case .guardianAssisting: return "Community Guardian assisting"
            }
        }
    }

    /// Identifier for the standing "journey active" notification — kept
    /// stable so posting again (or clearing) replaces/removes the same one
    /// instead of stacking duplicates in the notification center.
    private static let ongoingJourneyID = "guardian.ongoingJourney"

    /// A quiet, persistent notification shown for the duration of a journey
    /// so the user has visible, discreet confirmation that Guardian is still
    /// watching in the background — mirrors how ride-share/delivery apps
    /// signal an active background session, without revealing anything
    /// sensitive on the lock screen.
    func postOngoingJourneyNotification(destinationName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Guardian is watching your journey"
        content.body = "Tracking your trip to \(destinationName). Tap to open."
        content.sound = nil
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(identifier: Self.ongoingJourneyID,
                                            content: content, trigger: nil)
        center.add(request)
    }

    func clearOngoingJourneyNotification() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.ongoingJourneyID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.ongoingJourneyID])
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
