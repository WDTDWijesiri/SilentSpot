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
    var isSubmittedByCurrentUser: Bool = false

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
    var spotID: UUID? = nil

    var status: NoiseStatus { .classify(decibels) }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var hasValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && !(latitude == 0 && longitude == 0)
    }
}

struct BestTimeRecommendation {
    let startHour: Int
    let averageDB: Double
    let sampleCount: Int

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(hour: startHour)) ?? .now
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    static func calculate(for spot: QuietSpot, from measurements: [NoiseMeasurement]) -> BestTimeRecommendation? {
        let relevant = measurements.filter { measurement in
            measurement.spotID == spot.id || measurement.locationName == spot.name
        }
        guard !relevant.isEmpty else { return nil }

        let grouped = Dictionary(grouping: relevant) {
            Calendar.current.component(.hour, from: $0.timestamp)
        }
        guard let quietest = grouped.min(by: { left, right in
            let leftAverage = left.value.map(\.decibels).reduce(0, +) / Double(left.value.count)
            let rightAverage = right.value.map(\.decibels).reduce(0, +) / Double(right.value.count)
            return leftAverage < rightAverage
        }) else { return nil }

        return BestTimeRecommendation(
            startHour: quietest.key,
            averageDB: quietest.value.map(\.decibels).reduce(0, +) / Double(quietest.value.count),
            sampleCount: quietest.value.count
        )
    }
}

struct RewardBadge: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let isUnlocked: Bool
}

struct RewardItem: Identifiable, Hashable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let cost: Int

    static let catalogue: [RewardItem] = [
        RewardItem(
            id: "calm-listener",
            symbol: "headphones.circle.fill",
            title: "Calm Listener",
            detail: "A special profile title for regular noise contributors.",
            cost: 100
        ),
        RewardItem(
            id: "quiet-explorer",
            symbol: "safari.fill",
            title: "Quiet Explorer",
            detail: "Show the community that you discover peaceful places.",
            cost: 200
        ),
        RewardItem(
            id: "noise-guardian",
            symbol: "shield.lefthalf.filled",
            title: "Noise Guardian",
            detail: "A premium title for dedicated SilentSpot contributors.",
            cost: 350
        )
    ]
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: Self { self }
}

struct FocusPrompt: Identifiable {
    let id = UUID()
    let spotID: UUID
    let spotName: String
}

extension QuietSpot {
    func distance(from location: CLLocation?) -> Double? {
        guard let location else { return nil }
        let spotLocation = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: spotLocation) / 1_000
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
    case splash, onboarding, authentication, faceID, faceIDUnlock, main
}
