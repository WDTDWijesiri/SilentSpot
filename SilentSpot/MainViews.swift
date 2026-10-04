import Charts
import MapKit
import SwiftUI

enum MainTab: Hashable { case home, map, monitor, saved }

struct MainTabView: View {
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)
            NoiseMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(MainTab.map)
            MonitorView()
                .tabItem { Label("Monitor", systemImage: "waveform.circle.fill") }
                .tag(MainTab.monitor)
            FavouritesView()
                .tabItem { Label("Saved", systemImage: "heart.fill") }
                .tag(MainTab.saved)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: MainTab
    @State private var showingProfile = false
    @State private var showingReports = false
    @State private var selectedSpot: QuietSpot?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CURRENT NOISE STATUS").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            Text("Quiet").font(.largeTitle.bold()).foregroundStyle(AppTheme.quiet)
                            Text("Current Area • 38 dB").foregroundStyle(.secondary)
                        }
                    }
                    .background(AppTheme.softTeal, in: RoundedRectangle(cornerRadius: 18))

                    Button("Start Noise Measurement") { selection = .monitor }
                        .buttonStyle(PrimaryButtonStyle())

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        QuickAction(title: "Nearby Quiet Spots", symbol: "location.magnifyingglass") { selection = .map }
                        QuickAction(title: "Open Noise Map", symbol: "map.fill") { selection = .map }
                        QuickAction(title: "Favourite Spots", symbol: "heart.fill") { selection = .saved }
                        QuickAction(title: "Recent Activity", symbol: "chart.xyaxis.line") { showingReports = true }
                    }

                    if let nearby = store.spots.first {
                        Button { selectedSpot = nearby } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.circle.fill").font(.title2).foregroundStyle(AppTheme.quiet)
                                VStack(alignment: .leading) {
                                    Text(nearby.name).font(.headline).foregroundStyle(.primary)
                                    Text("Nearby • \(nearby.status.rawValue) • \(nearby.distanceKM, specifier: "%.1f") km")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(AppTheme.quiet.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("SilentSpot")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Profile", systemImage: "person.crop.circle") { showingProfile = true }
                }
            }
            .sheet(isPresented: $showingProfile) { NavigationStack { ProfileView() } }
            .sheet(isPresented: $showingReports) { NavigationStack { ReportsView() } }
            .navigationDestination(item: $selectedSpot) { SpotDetailsView(spot: $0) }
        }
    }
}

private struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(AppTheme.accent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text("View  →").font(.caption).foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator)))
        }
        .buttonStyle(.plain)
    }
}

struct MonitorView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var monitor: NoiseMonitor
    @EnvironmentObject private var locationService: LocationService
    @State private var didSave = false

    private var status: NoiseStatus { .classify(monitor.decibels) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Label("Current Location • NIBM Campus", systemImage: "location.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        Text("CURRENT NOISE LEVEL").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        Text("\(monitor.decibels, specifier: "%.0f") dB")
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                        Text(status.rawValue).font(.title3.bold()).foregroundStyle(status.color)
                        ProgressView(value: monitor.decibels, total: 100).tint(status.color)
                        Label(monitor.isMonitoring ? "Monitoring…" : "Ready to monitor", systemImage: monitor.isMonitoring ? "waveform" : "pause.circle")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(28)
                    .background(AppTheme.softTeal, in: RoundedRectangle(cornerRadius: 24))

                    Button("Start Monitoring", systemImage: "mic.fill") {
                        locationService.requestPermission()
                        Task { await monitor.start() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(monitor.isMonitoring)

                    Button("Stop & Save", systemImage: "stop.fill") {
                        let value = monitor.decibels
                        monitor.stop()
                        let coordinate = locationService.location?.coordinate
                        store.saveMeasurement(decibels: value, locationName: "NIBM Campus", latitude: coordinate?.latitude ?? 6.9068, longitude: coordinate?.longitude ?? 79.8700)
                        didSave = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!monitor.isMonitoring)

                    Label("Only the derived noise level, location and timestamp are saved. Raw audio and conversations are never stored.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding()
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Live Noise Monitoring")
            .alert("Measurement saved", isPresented: $didSave) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Location and timestamp were saved. You earned +10 points.")
            }
            .alert("Microphone permission needed", isPresented: $monitor.permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow microphone access in Settings to measure environmental sound levels.")
            }
        }
    }
}

struct FavouritesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.favourites) { spot in
                    NavigationLink(value: spot) { SpotRow(spot: spot) }
                }
            }
            .overlay {
                if store.favourites.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "heart", description: Text("Save a quiet spot to see it here."))
                }
            }
            .navigationTitle("Favourites")
            .navigationDestination(for: QuietSpot.self) { SpotDetailsView(spot: $0) }
        }
    }
}

struct SpotRow: View {
    let spot: QuietSpot
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spot.category.symbol)
                .frame(width: 38, height: 38)
                .foregroundStyle(spot.status.color)
                .background(spot.status.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name).font(.headline)
                Text("\(spot.currentDB, specifier: "%.0f") dB • \(spot.status.rawValue) • \(spot.distanceKM, specifier: "%.1f") km")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
