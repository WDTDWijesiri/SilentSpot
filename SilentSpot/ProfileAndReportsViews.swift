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

    private var filteredMeasurements: [NoiseMeasurement] {
        let calendar = Calendar.current
        return store.measurements.filter { measurement in
            switch period {
            case .today:
                calendar.isDateInToday(measurement.timestamp)
            case .week:
                calendar.dateInterval(of: .weekOfYear, for: .now)?.contains(measurement.timestamp) == true
            case .month:
                calendar.dateInterval(of: .month, for: .now)?.contains(measurement.timestamp) == true
            }
        }
    }
    private var chartData: [NoiseMeasurement] { Array(filteredMeasurements.prefix(50).reversed()) }
    private var averageNoise: Double {
        guard !filteredMeasurements.isEmpty else { return 0 }
        return filteredMeasurements.map(\.decibels).reduce(0, +) / Double(filteredMeasurements.count)
    }
    private var quietestMeasurement: NoiseMeasurement? { filteredMeasurements.min(by: { $0.decibels < $1.decibels }) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    MetricCard(value: filteredMeasurements.isEmpty ? "—" : averageNoise.formatted(.number.precision(.fractionLength(0))) + " dB", label: "Average noise")
                    MetricCard(value: quietestMeasurement?.locationName ?? "—", label: "Quietest place")
                    MetricCard(value: quietestMeasurement?.timestamp.formatted(date: .omitted, time: .shortened) ?? "—", label: "Quietest time")
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Noise history").font(.headline)
                        if chartData.isEmpty {
                            ContentUnavailableView("No measurements", systemImage: "chart.xyaxis.line", description: Text("No readings were saved in this period."))
                                .frame(height: 210)
                        } else {
                            Chart(chartData) { measurement in
                                LineMark(x: .value("Time", measurement.timestamp), y: .value("dB", measurement.decibels))
                                    .foregroundStyle(AppTheme.accent)
                                PointMark(x: .value("Time", measurement.timestamp), y: .value("dB", measurement.decibels))
                                    .foregroundStyle(measurement.status.color)
                            }
                            .chartYScale(domain: 25...100)
                            .frame(height: 210)
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contribution history").font(.headline)
                        ForEach(filteredMeasurements.prefix(10)) { measurement in
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
    @State private var showingRewards = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AppCard {
                    HStack(spacing: 14) {
                        Image(systemName: store.equippedReward?.symbol ?? "person.crop.circle.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.userName).font(.title2.bold())
                            Text("Profile Title: \(store.profileTitle)").font(.footnote).foregroundStyle(.secondary)
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
                        ForEach(store.rewardBadges) { badge in
                            BadgeView(badge: badge)
                        }
                    }
                }

                Button("Spend Points", systemImage: "gift.fill") { showingRewards = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Noise History & Reports", systemImage: "chart.xyaxis.line") { showingReports = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Notifications", systemImage: "bell.fill") { showingNotifications = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Profile & Settings", systemImage: "gearshape.fill") { showingSettings = true }
                    .buttonStyle(SecondaryButtonStyle())
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
        .sheet(isPresented: $showingRewards) { NavigationStack { RewardsShopView() } }
    }
}

struct RewardsShopView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var resultMessage = ""
    @State private var showingResult = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(AppTheme.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Available Balance").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(store.points) points").font(.title2.bold())
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Earn 10 points for a noise measurement and 50 points for submitting a new quiet spot.")
            }

            Section("Profile Rewards") {
                ForEach(store.rewards) { reward in
                    RewardShopRow(
                        reward: reward,
                        isPurchased: store.purchasedRewardIDs.contains(reward.id),
                        isEquipped: store.equippedRewardID == reward.id,
                        canAfford: store.points >= reward.cost,
                        isBusy: store.isBusy
                    ) {
                        Task { await use(reward) }
                    }
                }
            }
        }
        .navigationTitle("Rewards Shop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("Rewards", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    private func use(_ reward: RewardItem) async {
        let alreadyPurchased = store.purchasedRewardIDs.contains(reward.id)
        let success = alreadyPurchased
            ? await store.equipReward(reward)
            : await store.purchaseReward(reward)
        resultMessage = success
            ? (alreadyPurchased ? "\(reward.title) is now equipped." : "\(reward.title) was unlocked and equipped.")
            : (store.backendError ?? "The reward could not be updated.")
        showingResult = true
    }
}

private struct RewardShopRow: View {
    let reward: RewardItem
    let isPurchased: Bool
    let isEquipped: Bool
    let canAfford: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reward.symbol)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.softTeal, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(reward.title).font(.headline)
                Text(reward.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy || isEquipped || (!isPurchased && !canAfford))
        }
        .padding(.vertical, 5)
    }

    private var buttonTitle: String {
        if isEquipped { return "Equipped" }
        if isPurchased { return "Equip" }
        if canAfford { return "\(reward.cost)" }
        return "Need \(reward.cost)"
    }
}

private struct BadgeView: View {
    let badge: RewardBadge
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: badge.isUnlocked ? badge.symbol : "lock.fill")
                .font(.title)
                .foregroundStyle(badge.isUnlocked ? AppTheme.accent : .secondary)
            Text(badge.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
            Text(badge.isUnlocked ? "Unlocked" : badge.detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    @State private var showingPrivacy = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading) {
                        Text(store.userName).font(.headline)
                        Text("\(store.points) points • \(store.communityLevel)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Security & Alerts") {
                Toggle("Face ID", isOn: Binding(
                    get: { store.faceIDEnabled },
                    set: { enabled in Task { _ = await store.updateFaceID(enabled: enabled) } }
                ))
                Toggle("Notifications", isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task { store.setNotificationsEnabled(await NotificationService.requestPermission()) }
                        } else {
                            store.setNotificationsEnabled(false)
                        }
                    }
                ))
                Toggle("Favourite Focus Zones", isOn: Binding(
                    get: { store.focusZonesEnabled },
                    set: { enabled in
                        store.setFocusZonesEnabled(enabled)
                        locationService.syncFocusZones(spots: store.favourites, enabled: enabled)
                    }
                ))
            }
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { store.appearance },
                    set: store.setAppearance
                )) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
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
