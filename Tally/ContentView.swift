import SwiftUI
import OSLog
import SwiftData
import UIKit

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AdManager.self) private var adManager
    @Environment(\.modelContext) private var modelContext

    @State private var hasSeededTags = false
    @State private var didRefreshProStatus = false

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
        }
        .preferredColorScheme(.light)
        .onAppear {
            // Install the app-wide tap-to-dismiss-keyboard gesture here — the key
            // window exists by now (the AppDelegate lifecycle hook never fires under
            // SwiftUI's scene lifecycle). A short retry covers a not-yet-ready window.
            KeyboardDismissGesture.shared.install()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KeyboardDismissGesture.shared.install()
            }
            if !didRefreshProStatus {
                didRefreshProStatus = true
                Task { await SubscriptionService.refreshProStatus(appState: appState) }
            }
            seedDefaultTags()
            seedSystemTags()
            adManager.configure(isPro: appState.isPro)
        }
        .onChange(of: appState.subscriptionStatus) { _, _ in
            adManager.configure(isPro: appState.isPro)
        }
        .onChange(of: appState.debugForcePro) { _, _ in
            // Force Pro is separate from subscriptionStatus, so refresh ads when
            // it toggles or the debug switch wouldn't show/hide them live.
            adManager.configure(isPro: appState.isPro)
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
        // Present the expense detail from the root so tapping an expense from any
        // tab (home, reports drill-down) opens it in place instead of routing
        // through the home tab and colliding with its presentations.
        .sheet(item: $appState.selectedExpenseId) { id in
            ExpenseDetailView(expenseId: id)
        }
        .sheet(isPresented: $appState.showingSubscription) {
            SubscriptionView()
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
                Log.data.debug("default tags seeded")
            } catch {
                Log.data.error("seeding default tags failed: \(error.localizedDescription, privacy: .public)")
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
            Log.data.debug("system tags seeded")
        } catch {
            Log.data.error("seeding system tags failed: \(error.localizedDescription, privacy: .public)")
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
                Log.data.debug("migrated default tag colors")
            } catch {
                Log.data.error("migrating tag colors failed: \(error.localizedDescription, privacy: .public)")
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

// MARK: - Boot splash

/// Shown while the SwiftData store loads (see `TallyApp`). It renders and animates
/// *during* the real boot — the database/CloudKit store opens on a background task
/// behind it — instead of a fixed cosmetic delay after launch. No `@Query` or app
/// environment, so it's safe to show before the model container exists.
struct BootSplashView: View {
    private static let taglines = [
        "Decluttering your finances.",
        "Making expenses boring again.",
        "No spreadsheets were harmed.",
        "Just expenses. Nothing else.",
        "Your accountant will be so proud.",
        "Getting out of your way.",
        "Log it. Tag it. Done."
    ]
    @State private var shuffled = BootSplashView.taglines.shuffled()
    @State private var index = 0
    @State private var taglineOpacity: Double = 1
    @State private var taglineTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 80)
                Spacer(minLength: 0)
                IndeterminateBar()
                    .frame(height: 4)
                    .padding(.horizontal, 40)
                Spacer().frame(height: 16)
                Text(shuffled.isEmpty ? "" : shuffled[index % shuffled.count])
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandPrimary.opacity(0.7))
                    .opacity(taglineOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.light)
        .onAppear { rotateTaglines() }
        .onDisappear { taglineTask?.cancel() }
    }

    private func rotateTaglines() {
        taglineTask?.cancel()
        taglineTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 1.8...3.2)))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.3)) { taglineOpacity = 0 }
                try? await Task.sleep(for: .seconds(0.3))
                if Task.isCancelled { break }
                index += 1
                withAnimation(.easeInOut(duration: 0.3)) { taglineOpacity = 1 }
            }
        }
    }
}

/// A "fill-up" progress bar: a green capsule grows from empty to full on a
/// repeating loop, so it reads as active work during boot (unknown duration).
private struct IndeterminateBar: View {
    @State private var fill: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Capsule()
                .fill(Color.brandPrimary.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: max(0, w * fill))
                }
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                        fill = 1
                    }
                }
        }
    }
}
