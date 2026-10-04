import MapKit
import SwiftUI

struct NoiseMapView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @State private var position: MapCameraPosition = .region(.init(center: .init(latitude: 6.9068, longitude: 79.8700), span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
    @State private var selectedSpot: QuietSpot?
    @State private var showingAddSpot = false
    @State private var showingFinder = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(store.spots) { spot in
                        Annotation(spot.name, coordinate: spot.coordinate) {
                            Button { selectedSpot = spot } label: {
                                ZStack {
                                    Circle().fill(spot.status.color.opacity(0.24)).frame(width: 62, height: 62)
                                    Image(systemName: "circle.fill").foregroundStyle(spot.status.color)
                                }
                            }
                            .accessibilityLabel("\(spot.name), \(spot.status.rawValue)")
                        }
                    }
                }
                .mapControls { MapUserLocationButton(); MapCompass() }

                VStack(spacing: 10) {
                    HStack {
                        StatusPill(status: .quiet)
                        StatusPill(status: .moderate)
                        StatusPill(status: .noisy)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())

                    if let spot = selectedSpot {
                        MapSpotCard(spot: spot) { selectedSpot = nil }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding()
            }
            .navigationTitle("Live Noise Map")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Find", systemImage: "line.3.horizontal.decrease") { showingFinder = true }
                    Button("Add Quiet Spot", systemImage: "plus") { showingAddSpot = true }
                }
            }
            .sheet(isPresented: $showingAddSpot) { AddQuietSpotView() }
            .sheet(isPresented: $showingFinder) { NavigationStack { QuietSpotFinderView() } }
            .navigationDestination(for: QuietSpot.self) { SpotDetailsView(spot: $0) }
            .onAppear { locationService.requestPermission() }
        }
    }
}

private struct MapSpotCard: View {
    let spot: QuietSpot
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spot.name).font(.title3.bold())
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
            }
            Text("\(spot.status.rawValue) • Last measured \(spot.lastMeasured.formatted(.relative(presentation: .named)))")
                .font(.subheadline).foregroundStyle(spot.status.color)
            Text("\(spot.measurementCount) Community Measurements").font(.footnote).foregroundStyle(.secondary)
            NavigationLink(value: spot) { Text("View Details").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct QuietSpotFinderView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var quietOnly = true
    @State private var verifiedOnly = false

    private var results: [QuietSpot] {
        store.spots.filter { spot in
            (query.isEmpty || spot.name.localizedCaseInsensitiveContains(query)) &&
            (!quietOnly || spot.status == .quiet) &&
            (!verifiedOnly || spot.isVerified)
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Quiet now", isOn: $quietOnly)
                Toggle("Verified spots", isOn: $verifiedOnly)
            }
            Section("Nearby results") {
                ForEach(results) { spot in NavigationLink(value: spot) { SpotRow(spot: spot) } }
            }
        }
        .searchable(text: $query, prompt: "Search quiet spots")
        .navigationTitle("Quiet Spot Finder")
        .navigationDestination(for: QuietSpot.self) { SpotDetailsView(spot: $0) }
    }
}

struct SpotDetailsView: View {
    @EnvironmentObject private var store: AppStore
    let spot: QuietSpot
    @State private var showingMonitor = false
    @State private var showingVerification = false

    private var currentSpot: QuietSpot { store.spots.first(where: { $0.id == spot.id }) ?? spot }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(currentSpot.isVerified ? "Verified Quiet Spot" : "Pending Verification", systemImage: currentSpot.isVerified ? "checkmark.seal.fill" : "clock.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(currentSpot.isVerified ? AppTheme.quiet : AppTheme.warning)
                    Text(currentSpot.name).font(.largeTitle.bold())
                    Text(currentSpot.note).foregroundStyle(.secondary)
                    StatusPill(status: currentSpot.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AppCard {
                    VStack(spacing: 14) {
                        DetailRow(symbol: "location.fill", title: "Distance", value: currentSpot.distanceKM.formatted(.number.precision(.fractionLength(1))) + " km")
                        DetailRow(symbol: "clock.fill", title: "Best Time", value: currentSpot.bestTime)
                        DetailRow(symbol: "person.3.fill", title: "Community Measurements", value: "\(currentSpot.measurementCount)")
                    }
                }

                NoiseMiniChart(base: currentSpot.currentDB)

                Button("Measure Noise", systemImage: "waveform") { showingMonitor = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button(currentSpot.isFavourite ? "Remove from Favourites" : "Add to Favourites", systemImage: currentSpot.isFavourite ? "heart.slash" : "heart") {
                    store.toggleFavourite(currentSpot)
                }
                .buttonStyle(SecondaryButtonStyle())
                if !currentSpot.isVerified {
                    Button("Community Verification", systemImage: "person.3.sequence.fill") { showingVerification = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Spot Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMonitor) { NavigationStack { MonitorView() } }
        .sheet(isPresented: $showingVerification) { CommunityVerificationView(spot: currentSpot) }
    }
}

private struct DetailRow: View {
    let symbol: String
    let title: String
    let value: String
    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct NoiseMiniChart: View {
    let base: Double
    private var values: [Double] { [base + 8, base + 3, base, base + 6, base + 12, base + 4] }
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent noise").font(.headline)
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(values.enumerated()), id: \.offset) { item in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NoiseStatus.classify(item.element).color)
                            .frame(height: item.element * 1.4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .bottom)
            }
        }
    }
}

struct AddQuietSpotView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var monitor: NoiseMonitor
    @EnvironmentObject private var locationService: LocationService
    @State private var name = ""
    @State private var category: SpotCategory = .library
    @State private var note = ""
    @State private var measuredDB: Double?
    @State private var submittedSpot: QuietSpot?

    var body: some View {
        NavigationStack {
            Form {
                Section("Spot Name") { TextField("Enter spot name", text: $name) }
                Section("Current Location") { Label("Use current location", systemImage: "location.fill") }
                Section("Current Noise Measurement") {
                    if let measuredDB {
                        Text("\(measuredDB, specifier: "%.0f") dB • \(NoiseStatus.classify(measuredDB).rawValue)")
                    } else {
                        Text("Not measured yet")
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(SpotCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Optional Note") { TextField("Add a short note", text: $note, axis: .vertical) }
                Section {
                    Button("Measure Noise", systemImage: "waveform") {
                        Task {
                            if monitor.isMonitoring {
                                measuredDB = monitor.decibels
                                monitor.stop()
                            } else {
                                await monitor.start()
                            }
                        }
                    }
                    Button("Submit Quiet Spot", systemImage: "paperplane.fill") {
                        let coordinate = locationService.location?.coordinate
                        submittedSpot = store.submitSpot(name: name, category: category, note: note, decibels: measuredDB ?? monitor.decibels, latitude: coordinate?.latitude ?? 6.9068, longitude: coordinate?.longitude ?? 79.8700)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || measuredDB == nil)
                }
            }
            .navigationTitle("Add New Quiet Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
            .sheet(item: $submittedSpot, onDismiss: { dismiss() }) { CommunityVerificationView(spot: $0) }
        }
    }
}

struct CommunityVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let spot: QuietSpot

    private var currentSpot: QuietSpot { store.spots.first(where: { $0.id == spot.id }) ?? spot }
    private var progress: Double { min(1, Double(currentSpot.measurementCount) / Double(currentSpot.verificationTarget)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW QUIET SPOT").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            Text(currentSpot.name).font(.title.bold())
                            Text("Submitted by Thanuja").foregroundStyle(.secondary)
                            Label(currentSpot.isVerified ? "Verified Quiet Spot" : "Pending Verification", systemImage: currentSpot.isVerified ? "checkmark.seal.fill" : "clock.fill")
                                .foregroundStyle(currentSpot.isVerified ? AppTheme.quiet : AppTheme.warning)
                        }
                    }
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Community measurements").font(.headline)
                            Text("\(currentSpot.measurementCount) / \(currentSpot.verificationTarget)").font(.largeTitle.bold()).foregroundStyle(AppTheme.accent)
                            ProgressView(value: progress).tint(AppTheme.accent)
                            Text(currentSpot.isVerified ? "Enough measurements received." : "One more nearby measurement may be needed.").foregroundStyle(.secondary)
                        }
                    }
                    Button("Contribute a Measurement", systemImage: "waveform") {
                        store.contribute(to: currentSpot, decibels: 39)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Label("Measurements from different community members are combined to verify the spot.", systemImage: "person.3.fill")
                        .font(.footnote).foregroundStyle(.secondary).padding()
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Community Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
