import CoreLocation
import Foundation
import Testing
@testable import SilentSpot

struct SilentSpotModelTests {
    @Test("Noise levels are classified at every boundary")
    func noiseStatusBoundaries() {
        #expect(NoiseStatus.classify(0) == .quiet)
        #expect(NoiseStatus.classify(44.99) == .quiet)
        #expect(NoiseStatus.classify(45) == .moderate)
        #expect(NoiseStatus.classify(59.99) == .moderate)
        #expect(NoiseStatus.classify(60) == .noisy)
        #expect(NoiseStatus.classify(74.99) == .noisy)
        #expect(NoiseStatus.classify(75) == .veryNoisy)
    }

    @Test(
        "Firestore category aliases are decoded",
        arguments: [
            ("Café", SpotCategory.cafe),
            ("cafe", SpotCategory.cafe),
            ("coffee shop", SpotCategory.cafe),
            ("barista", SpotCategory.cafe),
            ("library", SpotCategory.library),
            ("study", SpotCategory.studyArea),
        ]
    )
    func categoryAliases(value: String, expected: SpotCategory) {
        #expect(SpotCategory.fromFirestore(value) == expected)
    }

    @Test("Unknown Firestore categories are rejected")
    func unknownCategory() {
        #expect(SpotCategory.fromFirestore("Cinema") == nil)
    }

    @Test("A zero coordinate is rejected even though Core Location accepts it")
    func measurementCoordinateValidation() {
        let invalid = measurement(latitude: 0, longitude: 0)
        let valid = measurement(latitude: 6.9271, longitude: 79.8612)

        #expect(invalid.hasValidCoordinate == false)
        #expect(valid.hasValidCoordinate)
    }

    @Test("Best-time recommendation selects the hour with the lowest average")
    func bestTimeSelectsQuietestAverage() throws {
        let spot = quietSpot()
        let calendar = Calendar(identifier: .gregorian)
        let day = DateComponents(year: 2026, month: 10, day: 24)
        let readings = [
            measurement(decibels: 38, spotID: spot.id, timestamp: try #require(calendar.date(from: dayWithHour(day, 8)))),
            measurement(decibels: 42, spotID: spot.id, timestamp: try #require(calendar.date(from: dayWithHour(day, 8)))),
            measurement(decibels: 56, spotID: spot.id, timestamp: try #require(calendar.date(from: dayWithHour(day, 14)))),
            measurement(decibels: 60, spotID: spot.id, timestamp: try #require(calendar.date(from: dayWithHour(day, 14)))),
        ]

        let result = try #require(BestTimeRecommendation.calculate(for: spot, from: readings))

        #expect(result.startHour == 8)
        #expect(result.averageDB == 40)
        #expect(result.sampleCount == 2)
    }

    @Test("Best-time calculation ignores measurements from other places")
    func bestTimeFiltersUnrelatedMeasurements() throws {
        let spot = quietSpot()
        let otherSpotID = UUID()
        let readings = [
            measurement(decibels: 40, spotID: spot.id, locationName: spot.name),
            measurement(decibels: 20, spotID: otherSpotID, locationName: "Other Place"),
        ]

        let result = try #require(BestTimeRecommendation.calculate(for: spot, from: readings))

        #expect(result.averageDB == 40)
        #expect(result.sampleCount == 1)
    }

    @Test("Best-time calculation returns nil without relevant measurements")
    func bestTimeWithoutData() {
        #expect(BestTimeRecommendation.calculate(for: quietSpot(), from: []) == nil)
    }

    @Test("Quiet-spot distance is calculated in kilometres")
    func distanceCalculation() throws {
        let spot = quietSpot(latitude: 6.9271, longitude: 79.8612)
        let sameLocation = CLLocation(latitude: 6.9271, longitude: 79.8612)

        let distance = try #require(spot.distance(from: sameLocation))

        #expect(abs(distance) < 0.001)
        #expect(spot.distance(from: nil) == nil)
    }

    @Test("Reward catalogue uses unique identifiers and positive costs")
    func rewardCatalogueIntegrity() {
        let identifiers = RewardItem.catalogue.map(\.id)

        #expect(Set(identifiers).count == identifiers.count)
        #expect(RewardItem.catalogue.allSatisfy { $0.cost > 0 })
    }

    private func quietSpot(
        latitude: Double = 6.9271,
        longitude: Double = 79.8612
    ) -> QuietSpot {
        QuietSpot(
            id: UUID(),
            name: "Central Library",
            latitude: latitude,
            longitude: longitude,
            currentDB: 40,
            category: .library,
            distanceKM: 0,
            lastMeasured: .now,
            measurementCount: 3,
            verificationTarget: 3,
            isVerified: true,
            isFavourite: false,
            note: "",
            bestTime: "8 AM – 9 AM"
        )
    }

    private func measurement(
        decibels: Double = 40,
        latitude: Double = 6.9271,
        longitude: Double = 79.8612,
        spotID: UUID? = nil,
        locationName: String = "Central Library",
        timestamp: Date = .now
    ) -> NoiseMeasurement {
        NoiseMeasurement(
            id: UUID(),
            decibels: decibels,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            timestamp: timestamp,
            spotID: spotID
        )
    }

    private func dayWithHour(_ day: DateComponents, _ hour: Int) -> DateComponents {
        var components = day
        components.hour = hour
        return components
    }
}
