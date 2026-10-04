import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            switch store.stage {
            case .splash: SplashView()
            case .onboarding: OnboardingView()
            case .authentication: AuthenticationView()
            case .faceID: FaceIDSetupView()
            case .main: MainTabView()
            }
        }
        .animation(.easeInOut, value: String(describing: store.stage))
    }
}

struct SplashView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 106))
                    .foregroundStyle(AppTheme.accent)
                Text("SilentSpot")
                    .font(.largeTitle.bold())
                Text("Find your calm, wherever you are.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Environmental noise • Private by design", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            store.completeSplash()
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0

    private let pages = [
        ("map.fill", "Discover quieter places", "See recent environmental noise estimates around you and compare nearby options."),
        ("waveform", "Measure without recording", "SilentSpot analyses sound level only. Conversations and raw audio are never stored."),
        ("clock.badge.checkmark.fill", "Know the best time to go", "Use historical patterns to find quieter hours for study, reading, and focused work.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 22) {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 28).fill(AppTheme.softTeal)
                            Image(systemName: pages[index].0)
                                .font(.system(size: 78))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .frame(height: 280)
                        Text(pages[index].1).font(.title.bold())
                        Text(pages[index].2).font(.title3).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(20)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == pages.count - 1 ? "Get started" : "Continue") {
                if page == pages.count - 1 { store.completeOnboarding() } else { page += 1 }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(20)
        }
        .background(AppTheme.background)
    }
}

struct AuthenticationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var creatingAccount = false
    @State private var name = "Thanuja"
    @State private var email = "student@example.com"
    @State private var password = "password"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(creatingAccount ? "Create your account" : "Welcome back")
                        .font(.largeTitle.bold())
                    Text(creatingAccount ? "Save places, receive quiet alerts, and keep your preferences in sync." : "Sign in to sync favourites and noise insights.")
                        .foregroundStyle(.secondary)
                    if creatingAccount {
                        TextField("Name", text: $name).textContentType(.name)
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password).textContentType(creatingAccount ? .newPassword : .password)
                    Button(creatingAccount ? "Create account" : "Sign in") { store.signIn() }
                        .buttonStyle(PrimaryButtonStyle())
                    if !creatingAccount {
                        Button("Continue with Apple", systemImage: "apple.logo") { store.signIn() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(creatingAccount ? "Already have an account? Sign in" : "New to SilentSpot? Create account") {
                        creatingAccount.toggle()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .textFieldStyle(.roundedBorder)
                .padding(20)
            }
            .background(AppTheme.background)
        }
    }
}

struct FaceIDSetupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var authenticating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 112))
                .foregroundStyle(AppTheme.accent)
            Text("Use Face ID?").font(.largeTitle.bold())
            Text("Unlock SilentSpot quickly while keeping your saved places and preferences private.")
                .font(.title3).foregroundStyle(.secondary)
            Spacer()
            Button(authenticating ? "Checking Face ID…" : "Enable Face ID") {
                authenticating = true
                Task {
                    let success = await AuthenticationService.authenticateWithFaceID()
                    store.finishFaceIDSetup(enabled: success)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Not now") { store.finishFaceIDSetup(enabled: false) }
                .buttonStyle(SecondaryButtonStyle())
            Text("You can change this later in Settings.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(AppTheme.background.ignoresSafeArea())
    }
}
