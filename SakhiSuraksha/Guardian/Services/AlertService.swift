//
//  AlertService.swift
//  Guardian
//
//  Sends a Telegram message + live-location pin and triggers an Omnidimension
//  AI voice call whenever SOS activates. Both calls are fire-and-forget so
//  they never block the emergency UI.
//
//  Credentials live in AppSecrets.swift (gitignored).
//

import Foundation
import CoreLocation
import Observation

@Observable
final class AlertService {

    private(set) var lastAlertAt: Date?
    private(set) var lastCallAt: Date?
    private(set) var telegramStatus: String = "Not sent"
    private(set) var callStatus: String = "Not triggered"

    // MARK: — Combined SOS trigger (call both in parallel)

    func sendSOSAlert(location: CLLocation?,
                      note: String,
                      senderName: String) async {
        async let tg:   Void = sendTelegramSOS(location: location, note: note, senderName: senderName)
        async let call: Void = triggerEmergencyCall(location: location, note: note)
        _ = await (tg, call)
        lastAlertAt = .now
    }

    // MARK: — Telegram

    func sendTelegramSOS(location: CLLocation?,
                         note: String,
                         senderName: String) async {
        let coordStr: String
        let mapLink: String
        if let loc = location {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            coordStr = String(format: "%.5f, %.5f", lat, lon)
            mapLink  = "https://maps.apple.com/?q=\(lat),\(lon)"
        } else {
            coordStr = "unavailable"
            mapLink  = ""
        }

        var lines: [String] = []
        lines.append("🚨 *EMERGENCY SOS — \(senderName)*")
        lines.append("")
        lines.append("🕐 *Time:* \(Date.now.formatted(date: .abbreviated, time: .standard))")
        if !note.isEmpty { lines.append("📝 *Note:* \(note)") }
        lines.append("📍 *Coordinates:* `\(coordStr)`")
        if !mapLink.isEmpty { lines.append("🗺 [Open in Maps](\(mapLink))") }
        lines.append("")
        lines.append("_Sent via SakhiSuraksha Guardian_")

        await telegramPost(endpoint: "sendMessage", body: [
            "chat_id":                 AppSecrets.telegramChatID,
            "text":                    lines.joined(separator: "\n"),
            "parse_mode":              "Markdown",
            "disable_web_page_preview": false
        ])
        guard !Task.isCancelled else { return }
        telegramStatus = "Message sent"

        // Follow with a live-location pin (5 minutes) — skipped if the user
        // already marked themselves safe (activateSOS's task was cancelled).
        if let loc = location {
            guard !Task.isCancelled else { return }
            await telegramPost(endpoint: "sendLocation", body: [
                "chat_id":     AppSecrets.telegramChatID,
                "latitude":    loc.coordinate.latitude,
                "longitude":   loc.coordinate.longitude,
                "live_period": 300
            ])
            guard !Task.isCancelled else { return }
            telegramStatus = "Message + live location sent"
        }
    }

    // MARK: — Omnidimension outbound call

    func triggerEmergencyCall(location: CLLocation?, note: String) async {
        // Omnidimension REST API: POST /api/v1/calls/dispatch
        // Auth: Authorization: Bearer <API_KEY>
        guard let url = URL(string: "https://backend.omnidim.io/api/v1/calls/dispatch") else { return }

        var callContext: [String: Any] = [
            "emergency_type": "SOS Alert",
            "app":            "SakhiSuraksha Guardian",
            "timestamp":      Date.now.formatted(date: .abbreviated, time: .standard)
        ]
        if let loc = location {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            callContext["location"]   = String(format: "%.5f, %.5f", lat, lon)
            callContext["maps_link"]  = "https://maps.apple.com/?q=\(lat),\(lon)"
        }
        if !note.isEmpty { callContext["user_note"] = note }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",                    forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(AppSecrets.omnidimAPIKey)",  forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "agent_id":       AppSecrets.omnidimAgentID,
            "from_number_id": AppSecrets.omnidimFromNumberID,
            "to_number":      AppSecrets.alertPhoneNumber,
            "call_context":   callContext
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard !Task.isCancelled else { return }
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse {
            // Never surface the raw API response — it can contain technical
            // JSON/error detail that's jarring during an active emergency.
            // The important fact for the user is only whether the call went
            // out, not why it didn't.
            callStatus = (http.statusCode == 200 || http.statusCode == 201)
                ? "Call dispatched ✓"
                : "Call couldn't be placed automatically — try 112 directly."
        } else {
            callStatus = "Call couldn't be placed automatically — try 112 directly."
        }
        guard !Task.isCancelled else { return }
        lastCallAt = .now
    }

    // MARK: — Helpers

    private func telegramPost(endpoint: String, body: [String: Any]) async {
        guard let url = URL(string: "https://api.telegram.org/bot\(AppSecrets.telegramBotToken)/\(endpoint)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
