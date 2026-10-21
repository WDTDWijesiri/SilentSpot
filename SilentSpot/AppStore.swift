import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var stage: AppStage = .splash
    @Published var spots: [QuietSpot] = []
    @Published var measurements: [NoiseMeasurement] = []
    @Published var communityMeasurements: [NoiseMeasurement] = []
    @Published var inbox: [AppNotification] = []
    @Published var points = 0
    @Published var lifetimePoints = 0
    @Published var purchasedRewardIDs: Set<String> = []
    @Published var equippedRewardID: String?
    @Published var userName = "User"
    @Published var notificationsEnabled: Bool
    @Published var faceIDEnabled: Bool
    @Published var focusZonesEnabled: Bool
    @Published var appearance: AppAppearance
    @Published var backendError: String?
    @Published var isBusy = false

    private let defaults = UserDefaults.standard
    private let firebase = FirebaseService()
    private var cancellables: Set<AnyCancellable> = []
    private var didBindFirebase = false
    private var quietFavouriteIDs: Set<UUID> = []
    private var hasObservedFavouriteState = false
    private var pendingCredentials: StoredLoginCredentials?

    init() {
        notificationsEnabled = defaults.object(forKey: "silentSpot.notificationsEnabled") as? Bool ?? true
        faceIDEnabled = defaults.bool(forKey: "silentSpot.faceIDEnabled")
        focusZonesEnabled = defaults.bool(forKey: "silentSpot.focusZonesEnabled")
        appearance = AppAppearance(rawValue: defaults.string(forKey: "silentSpot.appearance") ?? "") ?? .system
    }

    var favourites: [QuietSpot] { spots.filter(\.isFavourite) }
    var verifiedCount: Int { spots.filter { $0.isVerified && $0.isSubmittedByCurrentUser }.count }
    var contributionCount: Int { measurements.count }
    var isFirebaseConfigured: Bool { firebase.isConfigured }
    var canSignInWithFaceID: Bool { faceIDEnabled && BiometricCredentialStore.hasCredentials }
    var rewards: [RewardItem] { RewardItem.catalogue }
    var hasFocusTimer: Bool { purchasedRewardIDs.contains("calm-listener") }
    var hasSmartFinder: Bool { purchasedRewardIDs.contains("quiet-explorer") }
    var hasAdvancedReports: Bool { purchasedRewardIDs.contains("noise-guardian") }
    var totalEarnedPoints: Int {
        let spent = rewards
            .filter { purchasedRewardIDs.contains($0.id) }
            .reduce(0) { $0 + $1.cost }
        return max(lifetimePoints, points + spent)
    }
    var equippedReward: RewardItem? {
        rewards.first { $0.id == equippedRewardID && purchasedRewardIDs.contains($0.id) }
    }
    var profileTitle: String { equippedReward?.title ?? communityLevel }
    var communityLevel: String {
        switch totalEarnedPoints {
        case 500...: "Quiet Champion"
        case 200...: "Quiet Explorer"
        case 50...: "Spot Scout"
        default: "New Contributor"
        }
    }
    var rewardBadges: [RewardBadge] {
        [
            RewardBadge(id: "explorer", symbol: "safari.fill", title: "Quiet Explorer", detail: "Earn 200 points", isUnlocked: totalEarnedPoints >= 200),
            RewardBadge(id: "finder", symbol: "mappin.and.ellipse", title: "Spot Finder", detail: "Help verify a spot", isUnlocked: verifiedCount > 0),
            RewardBadge(id: "contributor", symbol: "person.3.fill", title: "Contributor", detail: "Add 10 measurements", isUnlocked: contributionCount >= 10)
        ]
    }

    func startFirebase() {
        firebase.start()
        bindFirebaseIfNeeded()
    }

    func completeSplash() {
        if firebase.isAuthenticated {
            stage = faceIDEnabled ? .faceIDUnlock : .main
        } else {
            stage = defaults.bool(forKey: "silentSpot.onboarded") ? .authentication : .onboarding
        }
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "silentSpot.onboarded")
        stage = .authentication
    }

    func signIn(email: String, password: String) async {
        await performAuthentication(credentials: StoredLoginCredentials(email: email, password: password)) {
            try await self.firebase.signIn(email: email, password: password)
        }
    }

    func signUp(name: String, email: String, password: String) async {
        await performAuthentication(credentials: StoredLoginCredentials(email: email, password: password)) {
            try await self.firebase.signUp(name: name, email: email, password: password)
        }
    }

    func signInWithFaceID() async {
        isBusy = true
        backendError = nil
        defer { isBusy = false }
        do {
            guard firebase.isConfigured else { throw FirebaseServiceError.notConfigured }
            let credentials = try await BiometricCredentialStore.load()
            try await firebase.signIn(email: credentials.email, password: credentials.password)
            stage = .main
        } catch {
            backendError = error.localizedDescription
        }
    }

    func finishFaceIDSetup(enabled: Bool) {
        faceIDEnabled = enabled
        defaults.set(enabled, forKey: "silentSpot.faceIDEnabled")
        if enabled, let credentials = pendingCredentials {
            do {
                try BiometricCredentialStore.save(email: credentials.email, password: credentials.password)
            } catch {
                faceIDEnabled = false
                defaults.set(false, forKey: "silentSpot.faceIDEnabled")
                backendError = error.localizedDescription
            }
        }
        pendingCredentials = nil
        stage = .main
    }

    func unlockWithFaceID() async -> Bool {
        let success = await AuthenticationService.authenticateWithFaceID()
        if success { stage = .main }
        return success
    }

    func updateFaceID(enabled: Bool) async -> Bool {
        if enabled {
            guard await AuthenticationService.authenticateWithFaceID() else { return false }
        } else {
            BiometricCredentialStore.delete()
        }
        faceIDEnabled = enabled
        defaults.set(enabled, forKey: "silentSpot.faceIDEnabled")
        return true
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "silentSpot.notificationsEnabled")
    }

    func setFocusZonesEnabled(_ enabled: Bool) {
        focusZonesEnabled = enabled
        defaults.set(enabled, forKey: "silentSpot.focusZonesEnabled")
    }

    func setAppearance(_ newValue: AppAppearance) {
        appearance = newValue
        defaults.set(newValue.rawValue, forKey: "silentSpot.appearance")
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
        Task {
            await performBackendWrite { try await self.firebase.setFavourite(spot, isFavourite: !spot.isFavourite) }
        }
    }

    func purchaseReward(_ reward: RewardItem) async -> Bool {
        isBusy = true
        backendError = nil
        defer { isBusy = false }
        do {
            try await firebase.purchaseReward(reward)
            await createNotification(
                symbol: "gift.fill",
                title: "Reward unlocked",
                message: "\(reward.title) is now equipped. You spent \(reward.cost) points."
            )
            return true
        } catch {
            backendError = error.localizedDescription
            return false
        }
    }

    func equipReward(_ reward: RewardItem) async -> Bool {
        isBusy = true
        backendError = nil
        defer { isBusy = false }
        do {
            try await firebase.equipReward(reward)
            return true
        } catch {
            backendError = error.localizedDescription
            return false
        }
    }

    func submitSpot(name: String, category: SpotCategory, note: String, decibels: Double, latitude: Double, longitude: Double) async -> QuietSpot? {
        let spot = QuietSpot(id: UUID(), name: name, latitude: latitude, longitude: longitude, currentDB: decibels, category: category, distanceKM: 0, lastMeasured: .now, measurementCount: 1, verificationTarget: 3, isVerified: false, isFavourite: false, note: note, bestTime: "Collecting data", isSubmittedByCurrentUser: true)
        backendError = nil
        do {
            try await firebase.submitSpot(spot)
            try await firebase.refreshCommunitySpots()
            return spot
        } catch {
            backendError = error.localizedDescription
            return nil
        }
    }

    func refreshCommunitySpots() async {
        do {
            try await firebase.refreshCommunitySpots()
        } catch {
            backendError = "Community quiet spots could not be refreshed: \(error.localizedDescription)"
        }
    }

    func refreshCommunityMapData() async {
        backendError = nil
        do {
            try await firebase.refreshCommunitySpots()
            try await firebase.refreshCommunityMeasurements()
        } catch {
            backendError = "Community map data could not be refreshed: \(error.localizedDescription)"
        }
    }

    func contribute(to spot: QuietSpot, decibels: Double, latitude: Double, longitude: Double) async -> Bool {
        backendError = nil
        do {
            let becameVerified = try await firebase.contribute(to: spot, decibels: decibels, latitude: latitude, longitude: longitude)
            if becameVerified {
                await createNotification(symbol: "trophy.fill", title: "Quiet spot verified", message: "\(spot.name) was verified. You earned bonus points.")
            }
            return true
        } catch {
            backendError = error.localizedDescription
            return false
        }
    }

    func recordFocusArrival(_ prompt: FocusPrompt) {
        Task {
            guard notificationsEnabled else { return }
            let item = AppNotification(
                symbol: "location.fill",
                title: "You arrived at \(prompt.spotName)",
                message: "Start a focus session in your saved quiet place?",
                date: .now
            )
            do { try await firebase.saveNotification(item) }
            catch { backendError = error.localizedDescription }
        }
    }

    private func bindFirebaseIfNeeded() {
        guard !didBindFirebase else { return }
        didBindFirebase = true
        firebase.$spots
            .sink { [weak self] updatedSpots in
                guard let self else { return }
                let currentQuietFavourites = Set(updatedSpots.filter { $0.isFavourite && $0.status == .quiet }.map(\.id))
                let newlyQuiet = currentQuietFavourites.subtracting(self.quietFavouriteIDs)
                self.spots = updatedSpots
                if self.hasObservedFavouriteState {
                    for spot in updatedSpots where newlyQuiet.contains(spot.id) {
                        Task {
                            await self.createNotification(
                                symbol: "bell.fill",
                                title: "\(spot.name) is currently quiet",
                                message: "Your favourite spot is measuring \(Int(spot.currentDB)) dB."
                            )
                        }
                    }
                }
                self.quietFavouriteIDs = currentQuietFavourites
                self.hasObservedFavouriteState = true
            }
            .store(in: &cancellables)
        firebase.$measurements.assign(to: &$measurements)
        firebase.$communityMeasurements.assign(to: &$communityMeasurements)
        firebase.$notifications.assign(to: &$inbox)
        firebase.$points.assign(to: &$points)
        firebase.$lifetimePoints.assign(to: &$lifetimePoints)
        firebase.$purchasedRewardIDs.assign(to: &$purchasedRewardIDs)
        firebase.$equippedRewardID.assign(to: &$equippedRewardID)
        firebase.$userName.assign(to: &$userName)
        firebase.$syncErrorMessage
            .compactMap { $0 }
            .sink { [weak self] message in self?.backendError = message }
            .store(in: &cancellables)
    }

    private func performAuthentication(credentials: StoredLoginCredentials, _ operation: @escaping () async throws -> Void) async {
        isBusy = true
        backendError = nil
        defer { isBusy = false }
        do {
            guard firebase.isConfigured else { throw FirebaseServiceError.notConfigured }
            try await operation()
            if defaults.object(forKey: "silentSpot.faceIDEnabled") == nil {
                pendingCredentials = credentials
                stage = .faceID
            } else {
                if faceIDEnabled {
                    do {
                        try BiometricCredentialStore.save(email: credentials.email, password: credentials.password)
                    } catch {
                        backendError = "Signed in successfully, but Face ID login could not be saved: \(error.localizedDescription)"
                    }
                }
                stage = .main
            }
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

    private func createNotification(symbol: String, title: String, message: String) async {
        guard notificationsEnabled else { return }
        let item = AppNotification(symbol: symbol, title: title, message: message, date: .now)
        do {
            try await firebase.saveNotification(item)
            await NotificationService.send(title: title, body: message)
        } catch {
            backendError = error.localizedDescription
        }
    }

}
