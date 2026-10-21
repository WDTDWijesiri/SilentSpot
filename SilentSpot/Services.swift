import AVFoundation
import Combine
import CoreLocation
import LocalAuthentication
import Security
import UserNotifications

@MainActor
final class NoiseMonitor: NSObject, ObservableObject {
    @Published private(set) var decibels: Double = 42
    @Published private(set) var isMonitoring = false
    @Published var permissionDenied = false
    @Published var audioErrorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false

    func start() async {
        guard !isMonitoring else { return }
        permissionDenied = false
        audioErrorMessage = nil
        let granted = await requestPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NoiseMonitorError.audioInputUnavailable
            }

            input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
                guard let samples = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0 else { return }

                var sum: Float = 0
                for index in 0..<frameCount {
                    let sample = samples[index]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameCount))
                let dbFS = 20 * log10(max(rms, 0.000_001))
                let estimatedDB = min(100, max(30, 90 + Double(dbFS)))

                Task { @MainActor [weak self] in
                    self?.decibels = estimatedDB
                }
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isMonitoring = true
        } catch {
            removeInputTapIfNeeded()
            audioEngine.stop()
            audioEngine.reset()
            try? session.setActive(false)
            audioErrorMessage = "The microphone is allowed, but the audio input could not start. Close other apps using the microphone and try again. (\(error.localizedDescription))"
        }
    }

    func stop() {
        removeInputTapIfNeeded()
        audioEngine.stop()
        audioEngine.reset()
        isMonitoring = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func removeInputTapIfNeeded() {
        guard hasInputTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInputTap = false
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default:
            return false
        }
    }
}

private enum NoiseMonitorError: Error {
    case audioInputUnavailable
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationErrorMessage: String?
    @Published var focusPrompt: FocusPrompt?
    let manager = CLLocationManager()
    private var focusSpots: [UUID: QuietSpot] = [:]
    private var triggeredFocusSpots: Set<UUID> = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        authorizationStatus = manager.authorizationStatus
        locationErrorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied:
            locationErrorMessage = "SilentSpot location access is denied. Select While Using the App in Settings."
        case .restricted:
            locationErrorMessage = "Location access is restricted on this iPhone."
        @unknown default:
            locationErrorMessage = "The current location permission could not be determined."
        }
    }

    func waitForLocation() async -> CLLocation? {
        requestPermission()
        // Wait for the user's response instead of querying service state on the main thread.
        var authorizationWaits = 0
        while manager.authorizationStatus == .notDetermined, authorizationWaits < 120 {
            try? await Task.sleep(for: .milliseconds(250))
            authorizationWaits += 1
        }

        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            if locationErrorMessage == nil {
                locationErrorMessage = "Location permission is not available. Select While Using the App in Settings."
            }
            return nil
        }

        if let current = validLocation(from: location ?? manager.location) { return current }

        // iOS 17+ async updates provide a second path if the delegate has not delivered yet.
        if let current = await fetchLiveLocation() {
            location = current
            locationErrorMessage = nil
            return current
        }

        if locationErrorMessage == nil {
            locationErrorMessage = "Location permission is allowed, but the iPhone has not produced a GPS reading yet. Move near a window or outdoors and tap Try Again."
        }
        return nil
    }

    private func fetchLiveLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location, location.horizontalAccuracy >= 0 {
                            return location
                        }
                    }
                } catch {
                    return nil
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func validLocation(from candidate: CLLocation?) -> CLLocation? {
        guard let candidate, candidate.horizontalAccuracy >= 0 else { return nil }
        return candidate
    }

    func syncFocusZones(spots: [QuietSpot], enabled: Bool) {
        focusSpots = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0) })
        manager.monitoredRegions
            .filter { $0.identifier.hasPrefix("silentspot.") }
            .forEach(manager.stopMonitoring(for:))

        guard enabled, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        for spot in spots.prefix(20) {
            let region = CLCircularRegion(
                center: spot.coordinate,
                radius: 120,
                identifier: "silentspot.\(spot.id.uuidString)"
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            locationErrorMessage = nil
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied {
            locationErrorMessage = "SilentSpot location access is denied. Select While Using the App in Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let current = locations.reversed().first(where: { $0.horizontalAccuracy >= 0 }) else { return }
        location = current
        locationErrorMessage = nil
        for (id, spot) in focusSpots {
            let distance = current.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
            if distance <= 120, !triggeredFocusSpots.contains(id) {
                triggeredFocusSpots.insert(id)
                focusPrompt = FocusPrompt(spotID: id, spotName: spot.name)
                Task { await NotificationService.send(title: "You arrived at \(spot.name)", body: "Your favourite quiet place is nearby. Start Focus Mode?") }
            } else if distance > 180 {
                triggeredFocusSpots.remove(id)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("silentspot."),
              let id = UUID(uuidString: String(region.identifier.dropFirst("silentspot.".count))),
              let spot = focusSpots[id] else { return }
        triggeredFocusSpots.insert(id)
        focusPrompt = FocusPrompt(spotID: id, spotName: spot.name)
        Task { await NotificationService.send(title: "You arrived at \(spot.name)", body: "Your favourite quiet place is nearby. Start Focus Mode?") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationError = error as? CLError else {
            locationErrorMessage = error.localizedDescription
            return
        }
        switch locationError.code {
        case .locationUnknown:
            // Temporary: continuous updates remain active and can recover.
            break
        case .denied:
            authorizationStatus = manager.authorizationStatus
            locationErrorMessage = "Location access is unavailable. Check Location Services and SilentSpot permission in Settings."
        default:
            locationErrorMessage = locationError.localizedDescription
        }
    }
}

enum AuthenticationService {
    static func authenticateWithFaceID() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock your quiet places and preferences")) ?? false
    }
}

nonisolated struct StoredLoginCredentials: Codable, Sendable {
    let email: String
    let password: String
}

nonisolated enum BiometricCredentialStore {
    private static let service = "com.thanuja.silentspot.biometric-login"
    private static let account = "firebase-login"
    private static let savedMarker = "silentSpot.hasBiometricCredentials"

    static var hasCredentials: Bool {
        UserDefaults.standard.bool(forKey: savedMarker)
    }

    static func save(email: String, password: String) throws {
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            throw BiometricCredentialError.keychain(accessError?.takeRetainedValue().localizedDescription ?? "Could not protect the login.")
        }

        let credentials = StoredLoginCredentials(email: email, password: password)
        let encoded = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)
        let query: [String: Any] = baseQuery.merging([
            kSecValueData as String: encoded,
            kSecAttrAccessControl as String: accessControl
        ]) { _, new in new }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricCredentialError.status(status)
        }
        UserDefaults.standard.set(true, forKey: savedMarker)
    }

    static func load() async throws -> StoredLoginCredentials {
        try await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.localizedReason = "Sign in to SilentSpot"
            let query: [String: Any] = baseQuery.merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context
            ]) { _, new in new }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else {
                throw BiometricCredentialError.status(status)
            }
            return try JSONDecoder().decode(StoredLoginCredentials.self, from: data)
        }.value
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: savedMarker)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum BiometricCredentialError: LocalizedError {
    case keychain(String)
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(message):
            return message
        case let .status(status):
            if status == errSecUserCanceled || status == errSecAuthFailed {
                return "Face ID sign-in was cancelled or could not verify you."
            }
            if status == errSecItemNotFound {
                return "No Face ID login is saved. Sign in with your password once to enable it."
            }
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Face ID login could not be completed."
        }
    }
}

enum NotificationService {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func send(title: String, body: String) async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async {
        guard interval > 0, await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
