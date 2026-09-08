//
//  SupportResourcesService.swift
//  Guardian
//
//  Official government helplines, One Stop Centres, and verified NGO structure.
//  Only resources that are real and verified are shown. NGO entries are from
//  our own database — not from any assumed external API.
//

import Foundation
import CoreLocation
import Observation
#if os(iOS)
import UIKit
#endif

// MARK: - Support resource model

struct SupportResource: Identifiable {
    let id = UUID()
    var name: String
    var description: String
    var phone: String?
    var coordinate: CLLocationCoordinate2D?
    var address: String?
    var type: ResourceType
    var isVerified: Bool
    var isGovernment: Bool
    var services: [String]
    var operatingHours: String?

    enum ResourceType: String {
        case helpline
        case oneStopCentre
        case ngo
        case hospital
        case police
        case shelter
        case legalAid
        case counselling
    }

    var distanceText: String? {
        nil // populated at runtime when user location is known
    }
}

// MARK: - NGO model (our own database)

struct VerifiedNGO: Identifiable {
    let id = UUID()
    var name: String
    var description: String
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?
    var services: [String]
    var isVerified: Bool
    var operatingHours: String?
    var emergencySupport: Bool

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Service

@Observable
final class SupportResourcesService {

    // MARK: Official helplines (India)
    // These are real, publicly available government numbers.

    let helplines: [SupportResource] = [
        SupportResource(
            name: "Emergency Services",
            description: "Integrated emergency response — police, fire, ambulance",
            phone: "112",
            type: .helpline,
            isVerified: true,
            isGovernment: true,
            services: ["Police", "Fire", "Ambulance"],
            operatingHours: "24/7"),
        SupportResource(
            name: "Women Helpline",
            description: "National helpline for women in distress",
            phone: "181",
            type: .helpline,
            isVerified: true,
            isGovernment: true,
            services: ["Counselling", "Emergency assistance", "Referral to One Stop Centre"],
            operatingHours: "24/7"),
        SupportResource(
            name: "Police",
            description: "Local police emergency",
            phone: "100",
            type: .police,
            isVerified: true,
            isGovernment: true,
            services: ["Emergency response"],
            operatingHours: "24/7"),
        SupportResource(
            name: "Ambulance",
            description: "Medical emergency ambulance",
            phone: "108",
            type: .hospital,
            isVerified: true,
            isGovernment: true,
            services: ["Medical emergency transport"],
            operatingHours: "24/7"),
        SupportResource(
            name: "National Commission for Women",
            description: "Complaints and support for women",
            phone: "7827170170",
            type: .helpline,
            isVerified: true,
            isGovernment: true,
            services: ["Complaints", "Legal guidance", "Support"],
            operatingHours: "Mon–Fri, 9am–5:30pm"),
        SupportResource(
            name: "Childline",
            description: "Child protection helpline",
            phone: "1098",
            type: .helpline,
            isVerified: true,
            isGovernment: true,
            services: ["Child protection", "Emergency support"],
            operatingHours: "24/7"),
        SupportResource(
            name: "iCall (TISS)",
            description: "Free, confidential psychosocial helpline run by the Tata Institute of Social Sciences",
            phone: "9152987821",
            type: .counselling,
            isVerified: true,
            isGovernment: false,
            services: ["Counselling", "Emotional support", "Referrals"],
            operatingHours: "Mon–Sat, 8am–10pm"),
        SupportResource(
            name: "KIRAN Mental Health Helpline",
            description: "Government of India 24/7 toll-free mental health rehabilitation helpline",
            phone: "18005990019",
            type: .helpline,
            isVerified: true,
            isGovernment: true,
            services: ["Mental health support", "Crisis counselling"],
            operatingHours: "24/7"),
    ]

    // MARK: One Stop Centres
    // One Stop Centres are government-run facilities for women affected by violence.
    // Real OSC locations should be loaded from a verified government database.
    // This is a placeholder structure — replace with real data from your admin system.

    let oneStopCentreNote = "One Stop Centres are government-run facilities providing medical, legal, police, and counselling support to women affected by violence. Find your nearest centre at oscms.wcd.nic.in or call 181."

    // MARK: NGO database (our own verified entries)
    // Add real verified NGOs here. Do NOT mark isVerified = true unless your
    // admin system has actually verified the organisation.

    var verifiedNGOs: [VerifiedNGO] = [
        // Example structure — replace with real verified entries
        // VerifiedNGO(
        //     name: "Example NGO",
        //     description: "Support for women in distress",
        //     latitude: 28.6315,
        //     longitude: 77.2167,
        //     phone: "+91-XXXXXXXXXX",
        //     services: ["Shelter", "Legal aid", "Counselling"],
        //     isVerified: false,
        //     emergencySupport: true)
    ]

    // MARK: Nearest resources

    func nearestHelplines() -> [SupportResource] {
        helplines
    }

    func nearestNGOs(to coordinate: CLLocationCoordinate2D, limit: Int = 5) -> [VerifiedNGO] {
        let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return verifiedNGOs
            .filter { $0.isVerified }
            .sorted {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: userLoc) <
                CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: userLoc)
            }
            .prefix(limit)
            .map { $0 }
    }

    func call(_ resource: SupportResource) {
        guard let phone = resource.phone,
              let url = URL(string: "tel://\(phone)") else { return }
        UIApplication.shared.open(url)
    }
}
