import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

@MainActor
final class FirebaseService: ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var spots: [QuietSpot] = []
    @Published private(set) var measurements: [NoiseMeasurement] = []
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var points = 0
    @Published private(set) var userName = "User"
    @Published private(set) var favouriteIDs: Set<UUID> = []

    private var listeners: [ListenerRegistration] = []
    private var authHandle: AuthStateDidChangeListenerHandle?

    func start() {
        guard FirebaseApp.app() != nil else {
            isConfigured = false
            return
        }
        isConfigured = true
        if authHandle == nil {
            authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                Task { @MainActor in
                    self?.isAuthenticated = user != nil
                    if let user { self?.listen(for: user.uid) } else { self?.clearRemoteState() }
                }
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try requireConfiguration()
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(name: String, email: String, password: String) async throws {
        try requireConfiguration()
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await Firestore.firestore().collection("users").document(result.user.uid).setData([
            "name": name,
            "email": email,
            "points": 0,
            "favouriteSpotIDs": [],
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func signOut() throws {
        try requireConfiguration()
        try Auth.auth().signOut()
    }

    func saveMeasurement(_ measurement: NoiseMeasurement) async throws {
        let uid = try userID()
        let data = measurementData(measurement, userID: uid)
        let database = Firestore.firestore()
        let batch = database.batch()
        batch.setData(data, forDocument: database.collection("measurements").document(measurement.id.uuidString))
        batch.setData(data, forDocument: database.collection("users").document(uid).collection("measurements").document(measurement.id.uuidString))
        batch.updateData(["points": FieldValue.increment(Int64(10))], forDocument: database.collection("users").document(uid))
        try await batch.commit()
    }

    func submitSpot(_ spot: QuietSpot) async throws {
        let uid = try userID()
        var data = spotData(spot)
        data["submittedBy"] = uid
        data["submittedByName"] = userName
        let database = Firestore.firestore()
        let batch = database.batch()
        batch.setData(data, forDocument: database.collection("quietSpots").document(spot.id.uuidString))
        batch.updateData(["points": FieldValue.increment(Int64(50))], forDocument: database.collection("users").document(uid))
        try await batch.commit()
    }

    func contribute(to spot: QuietSpot, decibels: Double, latitude: Double, longitude: Double) async throws {
        let uid = try userID()
        let database = Firestore.firestore()
        let spotReference = database.collection("quietSpots").document(spot.id.uuidString)
        let measurement = NoiseMeasurement(id: UUID(), decibels: decibels, latitude: latitude, longitude: longitude, locationName: spot.name, timestamp: .now)
        let measurementReference = database.collection("measurements").document(measurement.id.uuidString)
        let userMeasurementReference = database.collection("users").document(uid).collection("measurements").document(measurement.id.uuidString)
        let userReference = database.collection("users").document(uid)

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(spotReference)
                let oldCount = snapshot.data()?["measurementCount"] as? Int ?? 0
                let oldDB = snapshot.data()?["currentDB"] as? Double ?? decibels
                let newCount = oldCount + 1
                let newDB = ((oldDB * Double(oldCount)) + decibels) / Double(max(newCount, 1))
                let becameVerified = newCount >= (snapshot.data()?["verificationTarget"] as? Int ?? 3)
                transaction.updateData([
                    "currentDB": newDB,
                    "measurementCount": newCount,
                    "lastMeasured": Timestamp(date: .now),
                    "isVerified": becameVerified
                ], forDocument: spotReference)
                let data = self.measurementData(measurement, userID: uid, spotID: spot.id)
                transaction.setData(data, forDocument: measurementReference)
                transaction.setData(data, forDocument: userMeasurementReference)
                transaction.updateData(["points": FieldValue.increment(Int64(becameVerified ? 35 : 10))], forDocument: userReference)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func setFavourite(_ spot: QuietSpot, isFavourite: Bool) async throws {
        let uid = try userID()
        let value: Any = isFavourite ? FieldValue.arrayUnion([spot.id.uuidString]) : FieldValue.arrayRemove([spot.id.uuidString])
        try await Firestore.firestore().collection("users").document(uid).updateData(["favouriteSpotIDs": value])
    }

    private func listen(for uid: String) {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        let database = Firestore.firestore()

        listeners.append(database.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let data = snapshot?.data() else { return }
                self.userName = data["name"] as? String ?? "User"
                self.points = data["points"] as? Int ?? 0
                self.favouriteIDs = Set((data["favouriteSpotIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
                self.applyFavouriteState()
            }
        })

        listeners.append(database.collection("quietSpots").order(by: "lastMeasured", descending: true).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self else { return }
                self.spots = snapshot?.documents.compactMap { self.decodeSpot($0) } ?? []
                self.applyFavouriteState()
            }
        })

        listeners.append(database.collection("users").document(uid).collection("measurements").order(by: "timestamp", descending: true).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                self?.measurements = snapshot?.documents.compactMap { self?.decodeMeasurement($0) } ?? []
            }
        })

        listeners.append(database.collection("users").document(uid).collection("notifications").order(by: "date", descending: true).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                self?.notifications = snapshot?.documents.compactMap { document in
                    let data = document.data()
                    return AppNotification(
                        symbol: data["symbol"] as? String ?? "bell.fill",
                        title: data["title"] as? String ?? "SilentSpot",
                        message: data["message"] as? String ?? "",
                        date: (data["date"] as? Timestamp)?.dateValue() ?? .now
                    )
                } ?? []
            }
        })
    }

    private func applyFavouriteState() {
        spots = spots.map { spot in
            var updated = spot
            updated.isFavourite = favouriteIDs.contains(spot.id)
            return updated
        }
    }

    private func decodeSpot(_ document: QueryDocumentSnapshot) -> QuietSpot? {
        let data = document.data()
        guard let id = UUID(uuidString: document.documentID),
              let name = data["name"] as? String,
              let categoryValue = data["category"] as? String,
              let category = SpotCategory(rawValue: categoryValue) else { return nil }
        return QuietSpot(
            id: id,
            name: name,
            latitude: data["latitude"] as? Double ?? 0,
            longitude: data["longitude"] as? Double ?? 0,
            currentDB: data["currentDB"] as? Double ?? 0,
            category: category,
            distanceKM: data["distanceKM"] as? Double ?? 0,
            lastMeasured: (data["lastMeasured"] as? Timestamp)?.dateValue() ?? .now,
            measurementCount: data["measurementCount"] as? Int ?? 0,
            verificationTarget: data["verificationTarget"] as? Int ?? 3,
            isVerified: data["isVerified"] as? Bool ?? false,
            isFavourite: favouriteIDs.contains(id),
            note: data["note"] as? String ?? "",
            bestTime: data["bestTime"] as? String ?? "Collecting data"
        )
    }

    private func decodeMeasurement(_ document: QueryDocumentSnapshot) -> NoiseMeasurement? {
        let data = document.data()
        guard let id = UUID(uuidString: document.documentID) else { return nil }
        return NoiseMeasurement(
            id: id,
            decibels: data["decibels"] as? Double ?? 0,
            latitude: data["latitude"] as? Double ?? 0,
            longitude: data["longitude"] as? Double ?? 0,
            locationName: data["locationName"] as? String ?? "Current Location",
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now
        )
    }

    private func spotData(_ spot: QuietSpot) -> [String: Any] {
        [
            "name": spot.name,
            "latitude": spot.latitude,
            "longitude": spot.longitude,
            "currentDB": spot.currentDB,
            "category": spot.category.rawValue,
            "distanceKM": spot.distanceKM,
            "lastMeasured": Timestamp(date: spot.lastMeasured),
            "measurementCount": spot.measurementCount,
            "verificationTarget": spot.verificationTarget,
            "isVerified": spot.isVerified,
            "note": spot.note,
            "bestTime": spot.bestTime
        ]
    }

    private func measurementData(_ measurement: NoiseMeasurement, userID: String, spotID: UUID? = nil) -> [String: Any] {
        var data: [String: Any] = [
            "userID": userID,
            "decibels": measurement.decibels,
            "latitude": measurement.latitude,
            "longitude": measurement.longitude,
            "locationName": measurement.locationName,
            "timestamp": Timestamp(date: measurement.timestamp)
        ]
        if let spotID { data["spotID"] = spotID.uuidString }
        return data
    }

    private func requireConfiguration() throws {
        guard FirebaseApp.app() != nil else { throw FirebaseServiceError.notConfigured }
    }

    private func userID() throws -> String {
        try requireConfiguration()
        guard let uid = Auth.auth().currentUser?.uid else { throw FirebaseServiceError.notAuthenticated }
        return uid
    }

    private func clearRemoteState() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        spots = []
        measurements = []
        notifications = []
        points = 0
        favouriteIDs = []
    }
}

enum FirebaseServiceError: LocalizedError {
    case notConfigured
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Firebase is not configured. Add GoogleService-Info.plist to the SilentSpot target."
        case .notAuthenticated: "Sign in before accessing community data."
        }
    }
}
