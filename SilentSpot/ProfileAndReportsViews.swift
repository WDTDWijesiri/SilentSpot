import Charts
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var period: ReportPeriod = .week
    @State private var showingExporter = false

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
    private var previousMeasurements: [NoiseMeasurement] {
        guard let interval = currentInterval else { return [] }
        let calendar = Calendar.current
        let previousStart: Date?
        switch period {
        case .today: previousStart = calendar.date(byAdding: .day, value: -1, to: interval.start)
        case .week: previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start)
        case .month: previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start)
        }
        guard let previousStart else { return [] }
        let previousInterval = DateInterval(start: previousStart, end: interval.start)
        return store.measurements.filter { previousInterval.contains($0.timestamp) }
    }
    private var currentInterval: DateInterval? {
        let calendar = Calendar.current
        switch period {
        case .today:
            let start = calendar.startOfDay(for: .now)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: .now)
        case .month:
            return calendar.dateInterval(of: .month, for: .now)
        }
    }
    private var comparisonText: String {
        guard !filteredMeasurements.isEmpty, !previousMeasurements.isEmpty else {
            return "Save readings in both periods to calculate a comparison."
        }
        let previousAverage = previousMeasurements.map(\.decibels).reduce(0, +) / Double(previousMeasurements.count)
        let difference = averageNoise - previousAverage
        if abs(difference) < 0.5 { return "Average noise is about the same as the previous period." }
        return "Average noise is \(abs(difference).formatted(.number.precision(.fractionLength(1)))) dB \(difference < 0 ? "quieter" : "noisier") than the previous period."
    }
    private var csvText: String {
        let formatter = ISO8601DateFormatter()
        let rows = filteredMeasurements.map { measurement in
            let location = measurement.locationName.replacingOccurrences(of: "\"", with: "\"\"")
            return "\(formatter.string(from: measurement.timestamp)),\(measurement.decibels.formatted(.number.precision(.fractionLength(1)))),\(measurement.status.rawValue),\"\(location)\",\(measurement.latitude),\(measurement.longitude)"
        }
        return (["timestamp,decibels,status,location,latitude,longitude"] + rows).joined(separator: "\n")
    }

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

                if store.hasAdvancedReports {
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Noise Guardian Insights", systemImage: "shield.lefthalf.filled")
                                .font(.headline)
                                .foregroundStyle(AppTheme.accent)
                            Text(comparisonText)
                                .font(.subheadline)
                            HStack {
                                Label("\(filteredMeasurements.count) current", systemImage: "chart.bar.fill")
                                Spacer()
                                Label("\(previousMeasurements.count) previous", systemImage: "clock.arrow.circlepath")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Button("Export \(period.rawValue) CSV", systemImage: "square.and.arrow.up") {
                                showingExporter = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(filteredMeasurements.isEmpty)
                        }
                    }
                } else {
                    AppCard {
                        Label("Unlock Noise Guardian for period comparisons and CSV export.", systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Noise History & Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileExporter(
            isPresented: $showingExporter,
            document: NoiseCSVDocument(text: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: "SilentSpot-\(period.rawValue)-Report"
        ) { _ in }
    }
}

private struct NoiseCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
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
    @State private var showingFocusTimer = false

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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Reward Tools").font(.title2.bold())
                    RewardToolCard(
                        title: "Focus Timer",
                        detail: store.hasFocusTimer ? "25 or 50 minute focus sessions" : "Unlock Calm Listener for 100 points",
                        symbol: "timer",
                        isUnlocked: store.hasFocusTimer
                    ) {
                        if store.hasFocusTimer { showingFocusTimer = true } else { showingRewards = true }
                    }
                    RewardToolCard(
                        title: "Smart Finder",
                        detail: store.hasSmartFinder ? "Radius and sorting controls are active on the Map" : "Unlock Quiet Explorer for 200 points",
                        symbol: "location.magnifyingglass",
                        isUnlocked: store.hasSmartFinder
                    ) {
                        if !store.hasSmartFinder { showingRewards = true }
                    }
                    RewardToolCard(
                        title: "Advanced Reports",
                        detail: store.hasAdvancedReports ? "Comparisons and CSV export are available" : "Unlock Noise Guardian for 350 points",
                        symbol: "chart.xyaxis.line",
                        isUnlocked: store.hasAdvancedReports
                    ) {
                        if store.hasAdvancedReports { showingReports = true } else { showingRewards = true }
                    }
                }

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
        .sheet(isPresented: $showingFocusTimer) { NavigationStack { FocusTimerView() } }
    }
}

private struct RewardToolCard: View {
    let title: String
    let detail: String
    let symbol: String
    let isUnlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isUnlocked ? symbol : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(isUnlocked ? AppTheme.accent : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.softTeal, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isUnlocked ? "chevron.right" : "gift.fill")
                    .foregroundStyle(AppTheme.accent)
            }
            .padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator)))
        }
        .buttonStyle(.plain)
    }
}

struct FocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("silentSpot.focusEndTimestamp") private var endTimestamp = 0.0
    @AppStorage("silentSpot.focusDurationSeconds") private var durationSeconds = 25.0 * 60
    @State private var selectedMinutes = 25

    private let notificationID = "silentSpot.focusTimer.complete"

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, endTimestamp - context.date.timeIntervalSince1970)
                let running = remaining > 0
                VStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(AppTheme.softTeal, lineWidth: 18)
                        Circle()
                            .trim(from: 0, to: running ? remaining / max(durationSeconds, 1) : 0)
                            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Image(systemName: running ? "brain.head.profile.fill" : "timer")
                                .font(.title)
                                .foregroundStyle(AppTheme.accent)
                            Text(timeText(remaining))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                            Text(running ? "Focus session active" : "Ready to focus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 250, height: 250)

                    if running {
                        Button("End Session", systemImage: "stop.fill") { cancelSession() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            Picker("Duration", selection: $selectedMinutes) {
                Text("25 min").tag(25)
                Text("50 min").tag(50)
            }
            .pickerStyle(.segmented)
            .disabled(endTimestamp > Date.now.timeIntervalSince1970)

            Button("Start Focus Session", systemImage: "play.fill") { startSession() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(endTimestamp > Date.now.timeIntervalSince1970)

            Text("You can leave the app while the timer runs. SilentSpot will send a local alert when the session ends.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(AppTheme.background)
        .navigationTitle("Focus Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func startSession() {
        let seconds = TimeInterval(selectedMinutes * 60)
        durationSeconds = seconds
        endTimestamp = Date.now.addingTimeInterval(seconds).timeIntervalSince1970
        Task {
            await NotificationService.schedule(
                identifier: notificationID,
                title: "Focus session complete",
                body: "Great work — your \(selectedMinutes)-minute SilentSpot focus session is finished.",
                after: seconds
            )
        }
    }

    private func cancelSession() {
        endTimestamp = 0
        NotificationService.cancel(identifier: notificationID)
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
                Text("Earn 10 points for a noise measurement, points for community verification, and 50 points for submitting a new quiet spot.")
            }

            Section("Reward Tools & Titles") {
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
            ? (alreadyPurchased ? "\(reward.title) is now equipped." : "\(reward.title) and its tool were unlocked and equipped.")
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
                Toggle("Nearby Quiet Place Alerts", isOn: Binding(
                    get: { store.focusZonesEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                let notificationsAllowed = await NotificationService.requestPermission()
                                store.setNotificationsEnabled(notificationsAllowed)
                                store.setFocusZonesEnabled(notificationsAllowed)
                                if notificationsAllowed { locationService.requestPermission() }
                                locationService.syncFocusZones(spots: store.arrivalAlertSpots, enabled: notificationsAllowed)
                            }
                        } else {
                            store.setFocusZonesEnabled(false)
                            locationService.syncFocusZones(spots: [], enabled: false)
                        }
                    }
                ))
                Text("Alerts when you come within about 120 m of a quiet community spot. Choose Always Allow for notifications while SilentSpot is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
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
