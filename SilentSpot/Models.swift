import CoreLocation
import Foundation

enum NoiseStatus: String, Codable, CaseIterable {
    case quiet = "Quiet"
    case moderate = "Moderate"
    case noisy = "Noisy"
    case veryNoisy = "Very Noisy"

    static func classify(_ decibels: Double) -> NoiseStatus {
        switch decibels {
        case ..<45: return .quiet
        case ..<60: return .moderate
        case ..<75: return .noisy
        default: return .veryNoisy
        }
    }
}

enum SpotCategory: String, Codable, CaseIterable, Identifiable {
    case library = "Library"
    case cafe = "Café"
    case park = "Park"
    case studyArea = "Study Area"
    case other = "Other"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .library: "books.vertical.fill"
        case .cafe: "cup.and.saucer.fill"
        case .park: "leaf.fill"
        case .studyArea: "rectangle.and.pencil.and.ellipsis"
        case .other: "mappin.circle.fill"
        }
    }
}

struct QuietSpot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var currentDB: Double
    var category: SpotCategory
    var distanceKM: Double
    var lastMeasured: Date
    var measurementCount: Int
    var verificationTarget: Int
    var isVerified: Bool
    var isFavourite: Bool
    var note: String
    var bestTime: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var status: NoiseStatus { .classify(currentDB) }
}

struct NoiseMeasurement: Identifiable, Codable, Hashable {
    let id: UUID
    let decibels: Double
    let latitude: Double
    let longitude: Double
    let locationName: String
    let timestamp: Date

    var status: NoiseStatus { .classify(decibels) }
}

struct AppNotification: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let title: String
    let message: String
    let date: Date
}

enum AppStage {
    case splash, onboarding, authentication, faceID, main
}

extension QuietSpot {
    static let samples: [QuietSpot] = [
        QuietSpot(id: UUID(), name: "Central Library", latitude: 6.9068, longitude: 79.8700, currentDB: 36, category: .library, distanceKM: 0.4, lastMeasured: .now.addingTimeInterval(-600), measurementCount: 24, verificationTarget: 3, isVerified: true, isFavourite: true, note: "Quiet reading floors and reliable Wi-Fi.", bestTime: "8:00 AM – 10:00 AM"),
        QuietSpot(id: UUID(), name: "Green Study Garden", latitude: 6.9085, longitude: 79.8664, currentDB: 41, category: .park, distanceKM: 0.8, lastMeasured: .now.addingTimeInterval(-1_800), measurementCount: 2, verificationTarget: 3, isVerified: false, isFavourite: false, note: "Shaded outdoor seating.", bestTime: "7:30 AM – 9:30 AM"),
        QuietSpot(id: UUID(), name: "Riverside Café", latitude: 6.9037, longitude: 79.8728, currentDB: 54, category: .cafe, distanceKM: 1.2, lastMeasured: .now.addingTimeInterval(-3_600), measurementCount: 13, verificationTarget: 3, isVerified: true, isFavourite: false, note: "Calmer before lunch.", bestTime: "9:00 AM – 11:00 AM")
    ]
}
