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

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async {
        let granted = await requestPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
            ]
            recorder = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isMonitoring = true
            timer?.invalidate()
            let meterTimer = Timer(timeInterval: 0.35, target: self, selector: #selector(handleMeterTimer(_:)), userInfo: nil, repeats: true)
            timer = meterTimer
            RunLoop.main.add(meterTimer, forMode: .common)
        } catch {
            permissionDenied = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isMonitoring = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func updateMeter() {
        recorder?.updateMeters()
        let power = recorder?.averagePower(forChannel: 0) ?? -48
        decibels = min(100, max(30, 90 + Double(power)))
    }

    @objc private func handleMeterTimer(_ timer: Timer) {
        updateMeter()
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
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
