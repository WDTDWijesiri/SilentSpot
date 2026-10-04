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
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var hasValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && !(latitude == 0 && longitude == 0)
    }
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
