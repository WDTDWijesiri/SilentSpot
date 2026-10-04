import SwiftUI

@main
struct MyApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var locationService = LocationService()
    @StateObject private var noiseMonitor = NoiseMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(locationService)
                .environmentObject(noiseMonitor)
                .tint(Color("AccentColor"))
        }
    }
}
