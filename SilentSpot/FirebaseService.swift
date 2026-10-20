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
    @Published private(set) var communityMeasurements: [NoiseMeasurement] = []
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var points = 0
    @Published private(set) var lifetimePoints = 0
    @Published private(set) var purchasedRewardIDs: Set<String> = []
    @Published private(set) var equippedRewardID: String?
    @Published private(set) var userName = "User"
    @Published private(set) var favouriteIDs: Set<UUID> = []
    @Published private(set) var syncErrorMessage: String?

    private var listeners: [ListenerRegistration] = []
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var currentUserID: String?

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
            "lifetimePoints": 0,
            "purchasedRewardIDs": [],
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
        batch.updateData([
            "points": FieldValue.increment(Int64(10)),
            "lifetimePoints": FieldValue.increment(Int64(10))
        ], forDocument: database.collection("users").document(uid))
        try await batch.commit()
    }

    func submitSpot(_ spot: QuietSpot) async throws {
        let uid = try userID()
        var data = spotData(spot)
        data["submittedBy"] = uid
        data["submittedByName"] = userName
        data["contributorIDs"] = [uid]
        let database = Firestore.firestore()
        let batch = database.batch()
        batch.setData(data, forDocument: database.collection("quietSpots").document(spot.id.uuidString))
        batch.updateData([
            "points": FieldValue.increment(Int64(50)),
            "lifetimePoints": FieldValue.increment(Int64(50))
        ], forDocument: database.collection("users").document(uid))
        try await batch.commit()
    }

    func refreshCommunitySpots() async throws {
        _ = try userID()
        let snapshot = try await Firestore.firestore()
            .collection("quietSpots")
            .getDocuments(source: .server)
        spots = decodedSpots(from: snapshot.documents)
        syncErrorMessage = nil
        applyFavouriteState()
    }

    func refreshCommunityMeasurements() async throws {
        _ = try userID()
        let snapshot = try await Firestore.firestore()
            .collection("measurements")
            .order(by: "timestamp", descending: true)
            .limit(to: 500)
            .getDocuments(source: .server)
        communityMeasurements = snapshot.documents.compactMap(decodeMeasurement)
    }

    func contribute(to spot: QuietSpot, decibels: Double, latitude: Double, longitude: Double) async throws -> Bool {
        let uid = try userID()
        let database = Firestore.firestore()
        let spotReference = database.collection("quietSpots").document(spot.id.uuidString)
        let measurement = NoiseMeasurement(id: UUID(), decibels: decibels, latitude: latitude, longitude: longitude, locationName: spot.name, timestamp: .now, spotID: spot.id)
        let measurementReference = database.collection("measurements").document(measurement.id.uuidString)
        let userMeasurementReference = database.collection("users").document(uid).collection("measurements").document(measurement.id.uuidString)
        let userReference = database.collection("users").document(uid)

        let result = try await database.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(spotReference)
                let contributorIDs = snapshot.data()?["contributorIDs"] as? [String] ?? []
                let submittedBy = snapshot.data()?["submittedBy"] as? String
                guard submittedBy != uid, !contributorIDs.contains(uid) else {
                    throw FirebaseServiceError.alreadyContributed
                }
                let oldCount = snapshot.data()?["measurementCount"] as? Int ?? 0
                let oldDB = snapshot.data()?["currentDB"] as? Double ?? decibels
                let newCount = oldCount + 1
                let newDB = ((oldDB * Double(oldCount)) + decibels) / Double(max(newCount, 1))
                let wasVerified = snapshot.data()?["isVerified"] as? Bool ?? false
                let target = snapshot.data()?["verificationTarget"] as? Int ?? 3
                let isNowVerified = newCount >= target && NoiseStatus.classify(newDB) == .quiet
                let becameVerified = !wasVerified && isNowVerified
                transaction.updateData([
                    "currentDB": newDB,
                    "measurementCount": newCount,
                    "lastMeasured": Timestamp(date: .now),
                    "isVerified": isNowVerified,
                    "contributorIDs": FieldValue.arrayUnion([uid])
                ], forDocument: spotReference)
                let data = self.measurementData(measurement, userID: uid, spotID: spot.id)
                transaction.setData(data, forDocument: measurementReference)
                transaction.setData(data, forDocument: userMeasurementReference)
                let earnedPoints = Int64(becameVerified ? 35 : 10)
                transaction.updateData([
                    "points": FieldValue.increment(earnedPoints),
                    "lifetimePoints": FieldValue.increment(earnedPoints)
                ], forDocument: userReference)
                return becameVerified
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return result as? Bool ?? false
    }

    func saveNotification(_ notification: AppNotification) async throws {
        let uid = try userID()
        try await Firestore.firestore()
            .collection("users").document(uid)
            .collection("notifications").document(notification.id.uuidString)
            .setData([
                "userID": uid,
                "symbol": notification.symbol,
                "title": notification.title,
                "message": notification.message,
                "date": Timestamp(date: notification.date)
            ])
    }

    func setFavourite(_ spot: QuietSpot, isFavourite: Bool) async throws {
        let uid = try userID()
        let value: Any = isFavourite ? FieldValue.arrayUnion([spot.id.uuidString]) : FieldValue.arrayRemove([spot.id.uuidString])
        try await Firestore.firestore().collection("users").document(uid).updateData(["favouriteSpotIDs": value])
    }

    func purchaseReward(_ reward: RewardItem) async throws {
        let uid = try userID()
        let database = Firestore.firestore()
        let userReference = database.collection("users").document(uid)

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(userReference)
                let data = snapshot.data() ?? [:]
                let balance = data["points"] as? Int ?? 0
                let purchased = data["purchasedRewardIDs"] as? [String] ?? []
                guard !purchased.contains(reward.id) else {
                    throw FirebaseServiceError.rewardAlreadyPurchased
                }
                guard balance >= reward.cost else {
                    throw FirebaseServiceError.insufficientPoints(required: reward.cost, available: balance)
                }
                transaction.updateData([
                    "points": balance - reward.cost,
                    "purchasedRewardIDs": FieldValue.arrayUnion([reward.id]),
                    "equippedRewardID": reward.id
                ], forDocument: userReference)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func equipReward(_ reward: RewardItem) async throws {
        let uid = try userID()
        guard purchasedRewardIDs.contains(reward.id) else {
            throw FirebaseServiceError.rewardNotOwned
        }
        try await Firestore.firestore().collection("users").document(uid).updateData([
            "equippedRewardID": reward.id
        ])
    }

    private func listen(for uid: String) {
        currentUserID = uid
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        let database = Firestore.firestore()

        listeners.append(database.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let data = snapshot?.data() else { return }
                self.userName = data["name"] as? String ?? "User"
                self.points = data["points"] as? Int ?? 0
                self.lifetimePoints = data["lifetimePoints"] as? Int ?? self.points
                self.purchasedRewardIDs = Set(data["purchasedRewardIDs"] as? [String] ?? [])
                self.equippedRewardID = data["equippedRewardID"] as? String
                self.favouriteIDs = Set((data["favouriteSpotIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
                self.applyFavouriteState()
            }
        })

        // Sort locally so older shared spots without `lastMeasured` are not excluded.
        listeners.append(database.collection("quietSpots").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.syncErrorMessage = "Community quiet spots could not be loaded: \(error.localizedDescription)"
                    return
                }
                self.syncErrorMessage = nil
                self.spots = self.decodedSpots(from: snapshot?.documents ?? [])
                self.applyFavouriteState()
            }
        })

        listeners.append(database.collection("users").document(uid).collection("measurements").order(by: "timestamp", descending: true).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                self?.measurements = snapshot?.documents.compactMap { self?.decodeMeasurement($0) } ?? []
            }
        })

        listeners.append(database.collection("measurements").order(by: "timestamp", descending: true).limit(to: 500).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.syncErrorMessage = "Community measurements could not be loaded: \(error.localizedDescription)"
                    return
                }
                self.communityMeasurements = snapshot?.documents.compactMap(self.decodeMeasurement) ?? []
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
              let category = SpotCategory.fromFirestore(categoryValue) else { return nil }
        return QuietSpot(
            id: id,
            name: name,
            latitude: number(data["latitude"]),
            longitude: number(data["longitude"]),
            currentDB: number(data["currentDB"]),
            category: category,
            distanceKM: number(data["distanceKM"]),
            lastMeasured: (data["lastMeasured"] as? Timestamp)?.dateValue() ?? .distantPast,
            measurementCount: integer(data["measurementCount"]),
            verificationTarget: max(3, integer(data["verificationTarget"])),
            isVerified: data["isVerified"] as? Bool ?? false,
            isFavourite: favouriteIDs.contains(id),
            note: data["note"] as? String ?? "",
            bestTime: data["bestTime"] as? String ?? "Collecting data",
            submittedByName: data["submittedByName"] as? String ?? "Community member",
            isSubmittedByCurrentUser: data["submittedBy"] as? String == currentUserID,
            hasCurrentUserContributed: (data["contributorIDs"] as? [String] ?? []).contains(currentUserID ?? "")
        )
    }

    private func decodedSpots(from documents: [QueryDocumentSnapshot]) -> [QuietSpot] {
        documents.compactMap(decodeSpot).sorted { $0.lastMeasured > $1.lastMeasured }
    }

    private func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
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
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now,
            spotID: (data["spotID"] as? String).flatMap(UUID.init(uuidString:))
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
        communityMeasurements = []
        notifications = []
        points = 0
        lifetimePoints = 0
        purchasedRewardIDs = []
        equippedRewardID = nil
        favouriteIDs = []
        syncErrorMessage = nil
        currentUserID = nil
    }
}

enum FirebaseServiceError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case alreadyContributed
    case insufficientPoints(required: Int, available: Int)
    case rewardAlreadyPurchased
    case rewardNotOwned

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Firebase is not configured. Add GoogleService-Info.plist to the SilentSpot target."
        case .notAuthenticated: "Sign in before accessing community data."
        case .alreadyContributed: "You already contributed a verification measurement for this spot. Another community member must verify it."
        case let .insufficientPoints(required, available): "You need \(required) points for this reward. Your current balance is \(available)."
        case .rewardAlreadyPurchased: "This reward is already unlocked."
        case .rewardNotOwned: "Purchase this reward before equipping it."
        }
    }
}
