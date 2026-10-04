import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var stage: AppStage = .splash
    @Published var spots: [QuietSpot]
    @Published var measurements: [NoiseMeasurement]
    @Published var points = 320
    @Published var notificationsEnabled = true
    @Published var faceIDEnabled = true

    private let defaults = UserDefaults.standard
    private let spotsKey = "silentSpot.spots"
    private let measurementsKey = "silentSpot.measurements"

    init() {
        spots = Self.decode([QuietSpot].self, from: UserDefaults.standard.data(forKey: "silentSpot.spots")) ?? QuietSpot.samples
        measurements = Self.decode([NoiseMeasurement].self, from: UserDefaults.standard.data(forKey: "silentSpot.measurements")) ?? Self.sampleMeasurements
    }

    var favourites: [QuietSpot] { spots.filter(\.isFavourite) }
    var verifiedCount: Int { spots.filter(\.isVerified).count }
    var contributionCount: Int { measurements.count }

    let inbox: [AppNotification] = [
        AppNotification(symbol: "bell.fill", title: "Central Library is quiet", message: "Your favourite library is currently measuring 36 dB.", date: .now.addingTimeInterval(-420)),
        AppNotification(symbol: "trophy.fill", title: "Quiet spot verified", message: "Your submitted spot was verified. You earned +50 points.", date: .now.addingTimeInterval(-7_200)),
        AppNotification(symbol: "location.fill", title: "You arrived at a study location", message: "Start a 50-minute focus session?", date: .now.addingTimeInterval(-86_400))
    ]

    func completeSplash() {
        stage = defaults.bool(forKey: "silentSpot.onboarded") ? .authentication : .onboarding
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "silentSpot.onboarded")
        stage = .authentication
    }

    func signIn() { stage = .faceID }
    func finishFaceIDSetup(enabled: Bool) {
        faceIDEnabled = enabled
        stage = .main
    }

    func signOut() { stage = .authentication }

    func saveMeasurement(decibels: Double, locationName: String, latitude: Double, longitude: Double) {
        let measurement = NoiseMeasurement(id: UUID(), decibels: decibels, latitude: latitude, longitude: longitude, locationName: locationName, timestamp: .now)
        measurements.insert(measurement, at: 0)
        points += 10
        persist()
    }

    func toggleFavourite(_ spot: QuietSpot) {
        guard let index = spots.firstIndex(where: { $0.id == spot.id }) else { return }
        spots[index].isFavourite.toggle()
        persist()
    }

    func submitSpot(name: String, category: SpotCategory, note: String, decibels: Double, latitude: Double, longitude: Double) -> QuietSpot {
        let spot = QuietSpot(id: UUID(), name: name, latitude: latitude, longitude: longitude, currentDB: decibels, category: category, distanceKM: 0, lastMeasured: .now, measurementCount: 1, verificationTarget: 3, isVerified: false, isFavourite: false, note: note, bestTime: "Collecting data")
        spots.insert(spot, at: 0)
        points += 50
        persist()
        return spot
    }

    func contribute(to spot: QuietSpot, decibels: Double) {
        guard let index = spots.firstIndex(where: { $0.id == spot.id }) else { return }
        let oldCount = spots[index].measurementCount
        spots[index].currentDB = ((spots[index].currentDB * Double(oldCount)) + decibels) / Double(oldCount + 1)
        spots[index].measurementCount += 1
        spots[index].lastMeasured = .now
        if spots[index].measurementCount >= spots[index].verificationTarget {
            spots[index].isVerified = true
            points += 25
        }
        points += 10
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(spots), forKey: spotsKey)
        defaults.set(try? JSONEncoder().encode(measurements), forKey: measurementsKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static let sampleMeasurements: [NoiseMeasurement] = [
        NoiseMeasurement(id: UUID(), decibels: 38, latitude: 6.9068, longitude: 79.8700, locationName: "Central Library", timestamp: .now.addingTimeInterval(-1_200)),
        NoiseMeasurement(id: UUID(), decibels: 46, latitude: 6.9085, longitude: 79.8664, locationName: "Green Study Garden", timestamp: .now.addingTimeInterval(-86_400)),
        NoiseMeasurement(id: UUID(), decibels: 52, latitude: 6.9037, longitude: 79.8728, locationName: "Riverside Café", timestamp: .now.addingTimeInterval(-172_800))
    ]
}
