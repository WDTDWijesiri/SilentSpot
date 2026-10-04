import Charts
import CoreLocation
import SwiftUI

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var period: ReportPeriod = .week

    enum ReportPeriod: String, CaseIterable, Identifiable {
        case today = "Today", week = "Week", month = "Month"
        var id: Self { self }
    }

    private let chartData = [
        ("Mon", 38.0), ("Tue", 43), ("Wed", 51), ("Thu", 41), ("Fri", 47), ("Sat", 35), ("Sun", 39)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    MetricCard(value: "43 dB", label: "Average noise")
                    MetricCard(value: "Library", label: "Quietest place")
                    MetricCard(value: "8–10 AM", label: "Quietest time")
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Noise history").font(.headline)
                        Chart(chartData, id: \.0) { day, value in
                            LineMark(x: .value("Day", day), y: .value("dB", value))
                                .foregroundStyle(AppTheme.accent)
                            PointMark(x: .value("Day", day), y: .value("dB", value))
                                .foregroundStyle(NoiseStatus.classify(value).color)
                        }
                        .chartYScale(domain: 25...75)
                        .frame(height: 210)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contribution history").font(.headline)
                        ForEach(store.measurements.prefix(5)) { measurement in
                            HStack {
                                Image(systemName: "waveform.circle.fill").foregroundStyle(measurement.status.color)
                                VStack(alignment: .leading) {
                                    Text(measurement.locationName)
                                    Text(measurement.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(measurement.decibels, specifier: "%.0f") dB")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Noise History & Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.headline).foregroundStyle(AppTheme.accent)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator)))
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var showingSettings = false
    @State private var showingReports = false
    @State private var showingNotifications = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AppCard {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 58)).foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thanuja").font(.title2.bold())
                            Text("Community Level: Quiet Explorer").font(.footnote).foregroundStyle(.secondary)
                            Label("\(store.points) Points", systemImage: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
                        }
                    }
                }

                HStack(spacing: 10) {
                    MetricCard(value: "\(store.verifiedCount)", label: "Verified Spots")
                    MetricCard(value: "\(store.contributionCount)", label: "Contributions")
                    MetricCard(value: "\(store.favourites.count)", label: "Favourites")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Badges").font(.title2.bold())
                    HStack(spacing: 10) {
                        BadgeView(symbol: "safari.fill", title: "Quiet Explorer")
                        BadgeView(symbol: "mappin.and.ellipse", title: "Spot Finder")
                        BadgeView(symbol: "person.3.fill", title: "Contributor")
                    }
                }

                Button("Noise History & Reports", systemImage: "chart.xyaxis.line") { showingReports = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Notifications", systemImage: "bell.fill") { showingNotifications = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Profile & Settings", systemImage: "gearshape.fill") { showingSettings = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Rewards & Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingReports) { NavigationStack { ReportsView() } }
        .sheet(isPresented: $showingNotifications) { NavigationStack { NotificationsView() } }
    }
}

private struct BadgeView: View {
    let symbol: String
    let title: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.title).foregroundStyle(AppTheme.accent)
            Text(title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(AppTheme.softTeal, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List(store.inbox) { item in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol).foregroundStyle(AppTheme.accent).frame(width: 34, height: 34).background(AppTheme.softTeal, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.message).font(.subheadline).foregroundStyle(.secondary)
                    Text(item.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Notifications")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var locationService: LocationService
    @State private var notificationToggle = true
    @State private var showingPrivacy = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading) {
                        Text("Thanuja").font(.headline)
                        Text("\(store.points) points • Quiet Explorer").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Security & Alerts") {
                Toggle("Face ID", isOn: $store.faceIDEnabled)
                Toggle("Notifications", isOn: $notificationToggle)
                    .onChange(of: notificationToggle) { _, enabled in
                        if enabled { Task { store.notificationsEnabled = await NotificationService.requestPermission() } }
                        else { store.notificationsEnabled = false }
                    }
            }
            Section("Permissions") {
                LabeledContent("Location Permission", value: locationText)
                LabeledContent("Microphone Permission", value: "Requested when measuring")
            }
            Section("Privacy") {
                Text("Audio is never stored. Only derived noise levels, time, and required location are saved.")
                Button("Manage My Data & Privacy", systemImage: "hand.raised.fill") { showingPrivacy = true }
            }
            Section {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    store.signOut()
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showingPrivacy) { PrivacyView() }
    }

    private var locationText: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "While Using"
        case .denied, .restricted: "Not Allowed"
        case .notDetermined: "Not Requested"
        @unknown default: "Unknown"
        }
    }
}

private struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("What SilentSpot stores") {
                    Label("Derived noise level (dB estimate)", systemImage: "waveform")
                    Label("Required location", systemImage: "location.fill")
                    Label("Measurement timestamp", systemImage: "clock.fill")
                }
                Section("What SilentSpot never stores") {
                    Label("Raw audio", systemImage: "mic.slash.fill")
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right.fill")
                }
            }
            .navigationTitle("Privacy")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
