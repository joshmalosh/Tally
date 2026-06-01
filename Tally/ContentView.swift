import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AdManager.self) private var adManager
    @Environment(\.modelContext) private var modelContext

    @State private var hasSeededTags = false
    @State private var showSplash = true
    @State private var splashOpacity: Double = 1.0
    @State private var splashProgress: CGFloat = 0
    @State private var currentTaglineIndex = 0
    @State private var taglineOpacity: Double = 1
    @State private var taglineTimerTask: Task<Void, Never>?
    @State private var didRefreshProStatus = false

    private static let splashDuration: TimeInterval = 3.5
    private static let taglines = [
        "Decluttering your finances.",
        "Making expenses boring again.",
        "No spreadsheets were harmed.",
        "Just expenses. Nothing else.",
        "Your accountant will be so proud.",
        "Getting out of your way.",
        "Log it. Tag it. Done."
    ]
    @State private var shuffledTaglines: [String] = Self.taglines.shuffled()

    var body: some View {
        ZStack {
            // Pre-warms AddEntryPicker so the FAB sheet opens without cold layout.
            AddEntryPicker { _ in }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // HomeView is always present and rendering in the background.
            // It is invisible and non-interactive until onboarding completes.
            mainApp
                .opacity(hasCompletedOnboarding ? 1 : 0)
                .allowsHitTesting(hasCompletedOnboarding)

            // Onboarding covers HomeView until complete.
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }

            // Splash overlays everything after onboarding, fades out as before.
            if showSplash && hasCompletedOnboarding {
                splashOverlay
                    .opacity(splashOpacity)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            if !didRefreshProStatus {
                didRefreshProStatus = true
                Task { await SubscriptionService.refreshProStatus(appState: appState) }
            }
            seedDefaultTags()
            seedSystemTags()
            adManager.configure(isPro: appState.isPro)
            if !hasCompletedOnboarding {
                taglineTimerTask?.cancel()
                showSplash = false
                splashOpacity = 0
            } else {
                dismissSplash()
            }
        }
        .onChange(of: appState.subscriptionStatus) { _, _ in
            adManager.configure(isPro: appState.isPro)
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                dismissSplash()
            }
        }
    }

    // MARK: - Splash Overlay

    private var splashOverlay: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 80)

                Spacer(minLength: 0)

                progressBar

                Spacer().frame(height: 16)

                Text(shuffledTaglines.isEmpty ? "" : shuffledTaglines[currentTaglineIndex % shuffledTaglines.count])
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandPrimary.opacity(0.7))
                    .opacity(taglineOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startSplashAnimations()
        }
    }

    private var progressBar: some View {
        let barWidth = max(0, UIScreen.main.bounds.width - 80)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.brandPrimary.opacity(0.25))
                .frame(height: 4)
            Capsule()
                .fill(Color.brandPrimary)
                .frame(width: max(0, barWidth * splashProgress), height: 4)
        }
        .frame(height: 4)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    private func startSplashAnimations() {
        withAnimation(.linear(duration: Self.splashDuration)) {
            splashProgress = 1
        }
        scheduleNextTagline()
    }

    private func scheduleNextTagline() {
        taglineTimerTask?.cancel()
        let interval = Double.random(in: 1.8...3.2)
        taglineTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                taglineOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            currentTaglineIndex += 1
            withAnimation(.easeInOut(duration: 0.3)) {
                taglineOpacity = 1
            }
            guard !Task.isCancelled else { return }
            scheduleNextTagline()
        }
    }

    private func dismissSplash() {
        guard showSplash else { return }
        taglineTimerTask?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.splashDuration) {
            taglineTimerTask?.cancel()
            withAnimation(.easeOut(duration: 0.35)) {
                splashOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showSplash = false
            }
        }
    }

    // MARK: - Main App

    private var mainApp: some View {
        @Bindable var appState = appState

        return ZStack {
            Color.bgPrimary
                .ignoresSafeArea()

            HomeView()
                .animation(.easeInOut(duration: 0.3), value: appState.isPro)
        }
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showingExport) {
            ExportView()
        }
        .onChange(of: syncEngine.isOnline) { _, online in
            appState.isOffline = !online
        }
    }

    // MARK: - Setup

    private func seedDefaultTags() {
        guard !hasSeededTags else { return }
        hasSeededTags = true

        let descriptor = FetchDescriptor<TagModel>()
        let existingTags = (try? modelContext.fetch(descriptor)) ?? []

        if existingTags.isEmpty {
            for def in TagModel.defaults {
                let tag = TagModel(userId: nil, name: def.name, colorId: def.colorId, sortOrder: def.sortOrder)
                modelContext.insert(tag)
            }
            do {
                try modelContext.save()
                #if DEBUG
                print("[Tally] Default tags seeded.")
                #endif
            } catch {
                #if DEBUG
                print("[Tally] ERROR seeding tags: \(error)")
                #endif
            }
        } else {
            migrateDefaultTagColors(existingTags)
        }
    }

    // MARK: - System tag seeding (Section 7)

    private func seedSystemTags() {
        guard !UserDefaults.standard.bool(forKey: "tally_has_seeded_default_tags") else { return }
        UserDefaults.standard.set(true, forKey: "tally_has_seeded_default_tags")

        let descriptor = FetchDescriptor<TagModel>()
        let existingTags = (try? modelContext.fetch(descriptor)) ?? []
        let existingNames = Set(existingTags.map { $0.name })

        for def in TagModel.systemTags where !existingNames.contains(def.name) {
            let tag = TagModel(
                userId: nil,
                name: def.name,
                colorId: def.colorId,
                symbolName: def.symbolName,
                isSystemTag: true,
                sortOrder: def.sortOrder,
                showOnHome: def.showOnHome
            )
            modelContext.insert(tag)
        }

        do {
            try modelContext.save()
            #if DEBUG
            print("[Tally] System tags seeded.")
            #endif
        } catch {
            #if DEBUG
            print("[Tally] ERROR seeding system tags: \(error)")
            #endif
        }
    }

    private func migrateDefaultTagColors(_ tags: [TagModel]) {
        let expectedColors = Dictionary(uniqueKeysWithValues: TagModel.defaults.map { ($0.name, $0.colorId) })
        var changed = false

        for tag in tags {
            if let expected = expectedColors[tag.name], tag.colorId != expected {
                tag.colorId = expected
                changed = true
            }
        }

        if changed {
            do {
                try modelContext.save()
                #if DEBUG
                print("[Tally] Migrated default tag colors.")
                #endif
            } catch {
                #if DEBUG
                print("[Tally] ERROR migrating tag colors: \(error)")
                #endif
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                ExpenseModel.self,
                TagModel.self,
            ],
            inMemory: true
        )
        .environment(AppState())
        .environment(SyncEngine())
        .environment(AdManager())
}
