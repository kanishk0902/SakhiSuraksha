//
//  HelpRequestService.swift
//  Guardian
//
//  Contact-based only — Guardian has no live helper-matching backend. This
//  composes an SMS a trusted contact must read and respond to; it is not a
//  dispatch/marketplace system. Follows the same sms: URL-composition idiom
//  used by SOSView, JourneySetupView, and LocationSharingView.
//

import Foundation
import CoreLocation

final class HelpRequestService {

    func composeSMSURL(for request: HelpRequest, contact: EmergencyContact) -> URL? {
        let locStr = "https://maps.apple.com/?q=\(request.coordinate.latitude),\(request.coordinate.longitude)"
        var body = "I need help: \(request.needType). "
        if !request.note.isEmpty { body += "\(request.note). " }
        body += "My location: \(locStr)"
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let phone = contact.phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "sms:\(phone)&body=\(encoded)")
    }
}
