import SwiftUI
import WidgetKit

private struct NoiseEntry: TimelineEntry {
    let date: Date
    let decibels: Double?
    let location: String
    let measuredAt: Date?

    var status: String {
        guard let decibels else { return "No reading yet" }
        if decibels < 45 { return "Quiet" }
        if decibels < 65 { return "Moderate" }
        return "Noisy"
    }

    var tint: Color {
        guard let decibels else { return Color(red: 0.05, green: 0.52, blue: 0.49) }
        if decibels < 45 { return Color(red: 0.13, green: 0.63, blue: 0.40) }
        if decibels < 65 { return Color(red: 0.83, green: 0.48, blue: 0.05) }
        return Color(red: 0.88, green: 0.25, blue: 0.29)
    }
}

private struct NoiseProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoiseEntry {
        NoiseEntry(date: .now, decibels: 36, location: "Central Library", measuredAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (NoiseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoiseEntry>) -> Void) {
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func currentEntry() -> NoiseEntry {
        // A free Apple Personal Team cannot sign the App Groups entitlement.
        // Keep the widget installable; live app data can be enabled after joining
        // the Apple Developer Program and restoring the shared App Group.
        NoiseEntry(date: .now, decibels: nil, location: "Tap to open SilentSpot", measuredAt: nil)
    }
}

private struct NoiseWidgetView: View {
    let entry: NoiseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .font(.headline)
                Text("SilentSpot")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(entry.tint)
                    .frame(width: 9, height: 9)
            }
            .foregroundStyle(.secondary)

            if let decibels = entry.decibels {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(decibels.rounded()))")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("dB")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(entry.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.tint)
            } else {
                Text("Measure your area")
                    .font(.title3.bold())
                Text("Open the app to save a noise reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                Text(entry.location)
                    .lineLimit(1)
                if let measuredAt = entry.measuredAt {
                    Text("•")
                    Text(measuredAt, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [entry.tint.opacity(0.20), Color(uiColor: .systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SilentSpotNoiseWidget: Widget {
    let kind = "SilentSpotNoiseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoiseProvider()) { entry in
            NoiseWidgetView(entry: entry)
        }
        .configurationDisplayName("Latest Noise Level")
        .description("Quick access to environmental noise monitoring in SilentSpot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SilentSpotWidgetBundle: WidgetBundle {
    var body: some Widget {
        SilentSpotNoiseWidget()
    }
}
