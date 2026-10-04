import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var stage: AppStage = .splash
    @Published var spots: [QuietSpot] = []
    @Published var measurements: [NoiseMeasurement] = []
    @Published var inbox: [AppNotification] = []
    @Published var points = 0
    @Published var userName = "User"
    @Published var notificationsEnabled = true
    @Published var faceIDEnabled = true
    @Published var backendError: String?
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let firebase = FirebaseService()
    private var cancellables: Set<AnyCancellable> = []
    private var didBindFirebase = false

    var favourites: [QuietSpot] { spots.filter(\.isFavourite) }
    var verifiedCount: Int { spots.filter(\.isVerified).count }
    var contributionCount: Int { measurements.count }
    var isFirebaseConfigured: Bool { firebase.isConfigured }

    func startFirebase() {
        firebase.start()
        bindFirebaseIfNeeded()
    }

    func completeSplash() {
        if firebase.isAuthenticated {
            stage = .main
        } else {
            stage = defaults.bool(forKey: "silentSpot.onboarded") ? .authentication : .onboarding
        }
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "silentSpot.onboarded")
        stage = .authentication
    }

    func signIn(email: String, password: String) async {
        await performAuthentication {
            try await self.firebase.signIn(email: email, password: password)
        }
    }

    func signUp(name: String, email: String, password: String) async {
        await performAuthentication {
            try await self.firebase.signUp(name: name, email: email, password: password)
        }
    }

    func finishFaceIDSetup(enabled: Bool) {
        faceIDEnabled = enabled
        stage = .main
    }

    func signOut() {
        do {
            try firebase.signOut()
            stage = .authentication
        } catch {
            backendError = error.localizedDescription
        }
    }

    func saveMeasurement(decibels: Double, locationName: String, latitude: Double, longitude: Double) async -> Bool {
        let measurement = NoiseMeasurement(id: UUID(), decibels: decibels, latitude: latitude, longitude: longitude, locationName: locationName, timestamp: .now)
        backendError = nil
        do {
            try await firebase.saveMeasurement(measurement)
            return true
        } catch {
            backendError = error.localizedDescription
            return false
        }
    }

    func toggleFavourite(_ spot: QuietSpot) {
        Task { await performBackendWrite { try await self.firebase.setFavourite(spot, isFavourite: !spot.isFavourite) } }
    }

    func submitSpot(name: String, category: SpotCategory, note: String, decibels: Double, latitude: Double, longitude: Double) -> QuietSpot {
        let spot = QuietSpot(id: UUID(), name: name, latitude: latitude, longitude: longitude, currentDB: decibels, category: category, distanceKM: 0, lastMeasured: .now, measurementCount: 1, verificationTarget: 3, isVerified: false, isFavourite: false, note: note, bestTime: "Collecting data")
        Task { await performBackendWrite { try await self.firebase.submitSpot(spot) } }
        return spot
    }

    func contribute(to spot: QuietSpot, decibels: Double, latitude: Double = 0, longitude: Double = 0) {
        Task { await performBackendWrite { try await self.firebase.contribute(to: spot, decibels: decibels, latitude: latitude, longitude: longitude) } }
    }

    private func bindFirebaseIfNeeded() {
        guard !didBindFirebase else { return }
        didBindFirebase = true
        firebase.$spots.assign(to: &$spots)
        firebase.$measurements.assign(to: &$measurements)
        firebase.$notifications.assign(to: &$inbox)
        firebase.$points.assign(to: &$points)
        firebase.$userName.assign(to: &$userName)
    }

    private func performAuthentication(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        backendError = nil
        defer { isBusy = false }
        do {
            guard firebase.isConfigured else { throw FirebaseServiceError.notConfigured }
            try await operation()
            stage = .faceID
        } catch {
            backendError = error.localizedDescription
        }
    }

    private func performBackendWrite(_ operation: @escaping () async throws -> Void) async {
        backendError = nil
        do {
            try await operation()
        } catch {
            backendError = error.localizedDescription
        }
    }
}
