import MapKit
import SwiftUI

struct NoiseMapView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @State private var position: MapCameraPosition = .region(.init(center: .init(latitude: 6.9068, longitude: 79.8700), span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
    @State private var selectedSpot: QuietSpot?
    @State private var selectedMeasurement: NoiseMeasurement?
    @State private var showingAddSpot = false
    @State private var showingFinder = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(store.spots) { spot in
                        Annotation(spot.name, coordinate: spot.coordinate) {
                            Button {
                                selectedMeasurement = nil
                                selectedSpot = spot
                            } label: {
                                ZStack {
                                    Circle().fill(spot.status.color.opacity(0.24)).frame(width: 62, height: 62)
                                    Image(systemName: "circle.fill").foregroundStyle(spot.status.color)
                                }
                            }
                            .accessibilityLabel("\(spot.name), \(spot.status.rawValue)")
                        }
                    }
                    ForEach(store.measurements.filter(\.hasValidCoordinate)) { measurement in
                        Annotation("Saved measurement", coordinate: measurement.coordinate) {
                            Button {
                                selectedSpot = nil
                                selectedMeasurement = measurement
                            } label: {
                                ZStack {
                                    Circle().fill(measurement.status.color.opacity(0.22)).frame(width: 48, height: 48)
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(measurement.status.color)
                                        .background(.white, in: Circle())
                                }
                            }
                            .accessibilityLabel("Saved measurement, \(measurement.status.rawValue), \(measurement.decibels.formatted()) decibels")
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
                    if let measurement = selectedMeasurement {
                        MapMeasurementCard(measurement: measurement) { selectedMeasurement = nil }
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
            .onAppear {
                locationService.requestPermission()
                focusLatestMeasurement()
            }
            .onChange(of: store.measurements.first?.id) { _, _ in
                focusLatestMeasurement()
            }
        }
    }

    private func focusLatestMeasurement() {
        guard let measurement = store.measurements.first(where: \.hasValidCoordinate) else { return }
        selectedSpot = nil
        selectedMeasurement = measurement
        position = .region(.init(
            center: measurement.coordinate,
            span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }
}

private struct MapMeasurementCard: View {
    let measurement: NoiseMeasurement
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Your saved measurement", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
            }
            Text("\(measurement.decibels, specifier: "%.0f") dB • \(measurement.status.rawValue)")
                .font(.title3.bold())
                .foregroundStyle(measurement.status.color)
            Text(measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
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

                NoiseMiniChart(measurements: store.measurements.filter { $0.locationName == currentSpot.name })

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
    let measurements: [NoiseMeasurement]
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent noise").font(.headline)
                if measurements.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "chart.bar", description: Text("Contribute a measurement at this spot."))
                        .frame(height: 120)
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(measurements.prefix(8)) { measurement in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(measurement.status.color)
                                .frame(height: max(18, measurement.decibels * 1.4))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .bottom)
                }
            }
        }
    }
}

struct AddQuietSpotView: View {
    private enum Field: Hashable { case name, note }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var monitor: NoiseMonitor
    @EnvironmentObject private var locationService: LocationService
    @State private var name = ""
    @State private var category: SpotCategory = .library
    @State private var note = ""
    @State private var measuredDB: Double?
    @State private var submittedSpot: QuietSpot?
    @State private var locationUnavailable = false
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Spot Name").font(.headline).foregroundStyle(.secondary)
                    TextField("Enter spot name", text: $name)
                        .focused($focusedField, equals: .name)
                        .textContentType(.location)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }
                        .padding()
                        .frame(minHeight: 54)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(focusedField == .name ? AppTheme.accent : Color(.separator), lineWidth: focusedField == .name ? 2 : 1))

                    Text("Current Location").font(.headline).foregroundStyle(.secondary)
                    Button {
                        locationService.requestPermission()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill").foregroundStyle(AppTheme.accent)
                            Text(locationService.location == nil ? "Use current location" : "Current location ready")
                            Spacer()
                            if locationService.location != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.quiet)
                            }
                        }
                        .padding()
                        .frame(minHeight: 54)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    Text("Current Noise Measurement").font(.headline).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                    if let measuredDB {
                        Text("\(measuredDB, specifier: "%.0f") dB • \(NoiseStatus.classify(measuredDB).rawValue)")
                    } else {
                        Text("Not measured yet")
                    }
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(minHeight: 54)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Category").font(.headline).foregroundStyle(.secondary)
                    Picker("Category", selection: $category) {
                        ForEach(SpotCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Optional Note").font(.headline).foregroundStyle(.secondary)
                    TextField("Add a short note", text: $note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .lineLimit(2...4)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding()
                        .frame(minHeight: 64, alignment: .top)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(focusedField == .note ? AppTheme.accent : Color(.separator), lineWidth: focusedField == .note ? 2 : 1))

                    Button("Measure Noise", systemImage: "waveform") {
                        focusedField = nil
                        Task {
                            if monitor.isMonitoring {
                                measuredDB = monitor.decibels
                                monitor.stop()
                            } else {
                                await monitor.start()
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Submit Quiet Spot", systemImage: "paperplane.fill") {
                        focusedField = nil
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            guard let coordinate = await locationService.waitForLocation()?.coordinate else {
                                locationUnavailable = true
                                return
                            }
                            submittedSpot = store.submitSpot(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                category: category,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                decibels: measuredDB ?? monitor.decibels,
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            )
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || measuredDB == nil || isSubmitting)

                    if isSubmitting { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle("Add New Quiet Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .sheet(item: $submittedSpot, onDismiss: { dismiss() }) { CommunityVerificationView(spot: $0) }
            .alert("Location needed", isPresented: $locationUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A current location is required before this quiet spot can be submitted.")
            }
            .onAppear { locationService.requestPermission() }
        }
    }
}

struct CommunityVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var monitor: NoiseMonitor
    @EnvironmentObject private var locationService: LocationService
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
                            Text("Submitted by \(store.userName)").foregroundStyle(.secondary)
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
                    Button(monitor.isMonitoring ? "Stop & Contribute" : "Start Measurement", systemImage: monitor.isMonitoring ? "stop.fill" : "waveform") {
                        if monitor.isMonitoring {
                            let coordinate = locationService.location?.coordinate
                            let value = monitor.decibels
                            monitor.stop()
                            store.contribute(to: currentSpot, decibels: value, latitude: coordinate?.latitude ?? 0, longitude: coordinate?.longitude ?? 0)
                        } else {
                            locationService.requestPermission()
                            Task { await monitor.start() }
                        }
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
