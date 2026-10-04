import AVFoundation
import Combine
import CoreLocation
import LocalAuthentication
import UserNotifications

@MainActor
final class NoiseMonitor: NSObject, ObservableObject {
    @Published private(set) var decibels: Double = 42
    @Published private(set) var isMonitoring = false
    @Published var permissionDenied = false

    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false

    func start() async {
        guard !isMonitoring else { return }
        permissionDenied = false
        let granted = await requestPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
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
            try? session.setActive(false)
            permissionDenied = true
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
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
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
    let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.requestLocation()
        default:
            break
        }
    }

    func waitForLocation() async -> CLLocation? {
        requestPermission()
        if let current = location ?? manager.location { return current }

        // Give Core Location time to deliver its first GPS/simulated reading.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if let current = location ?? manager.location { return current }
        }
        return nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `.locationUnknown` is temporary; continuous updates can still deliver
        // a valid GPS reading shortly afterwards.
        guard let locationError = error as? CLError,
              locationError.code == .locationUnknown else { return }
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

enum NotificationService {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}
