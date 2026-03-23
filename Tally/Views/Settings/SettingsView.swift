import SwiftUI
import SwiftData
import UserNotifications
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    @State private var showingSubscription = false
    @State private var showingCustomerCenter = false
    @State private var showingCurrencyPicker = false
    @State private var showingTagCreation = false
    @State private var showingGroupCreation = false
    @State private var editingTag: TagModel?

    /// All tags (standalone + group children), sorted A–Z
    private var allTagsSorted: [TagModel] {
        tags.filter { !$0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Groups only, sorted A–Z
    private var groupsSorted: [TagModel] {
        tags.filter { $0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func childrenOf(_ group: TagModel) -> [TagModel] {
        tags.filter { $0.parentId == group.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Subscription") {
                    if appState.isPro {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Pro")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("Active")
                                .font(Fonts.caption(13))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.success)
                        }

                        Button {
                            showingCustomerCenter = true
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandPrimary)
                                Text("Manage subscription")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    } else {
                        Button {
                            showingSubscription = true
                        } label: {
                            HStack {
                                Image(systemName: "star.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Go Pro")
                                        .foregroundStyle(Color.brandPrimary)
                                    Text("Unlimited exports, PDF, OCR, no ads")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Text("$4.99/mo")
                                    .font(Fonts.caption(13))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Recurring expense alerts", isOn: Binding(
                        get: { appState.recurringNotificationEnabled },
                        set: { newValue in
                            appState.recurringNotificationEnabled = newValue
                            if newValue {
                                Task {
                                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                }
                            }
                        }
                    ))
                    .tint(Color.brandPrimary)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified at 10am when recurring expenses are auto-logged.")
                }

                Section("Preferences") {
                    Button { showingCurrencyPicker = true } label: {
                        HStack {
                            Image(systemName: "coloncurrencysign.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Default currency")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(CurrencyFormatter.shared.symbol(for: appState.defaultCurrency)) \(appState.defaultCurrency)")
                                .font(Fonts.caption(14))
                                .foregroundStyle(Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }

                Section {
                    ForEach(allTagsSorted) { tag in
                        HStack(spacing: Spacing.smd) {
                            Button {
                                editingTag = tag
                            } label: {
                                HStack(spacing: Spacing.smd) {
                                    Circle()
                                        .fill(tag.tagColor.primaryColor)
                                        .frame(width: 12, height: 12)
                                    Text(tag.name)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .buttonStyle(.plain)
                            Toggle("", isOn: Binding(
                                get: { tag.showOnHome },
                                set: { tag.showOnHome = $0 }
                            ))
                            .labelsHidden()
                            .tint(Color.brandPrimary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { deleteTag(tag) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showingTagCreation = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Add tag")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Choose which tags appear as filters on the home screen.")
                }

                Section("Groups") {
                    ForEach(groupsSorted) { group in
                        NavigationLink {
                            GroupDetailView(group: group)
                        } label: {
                            HStack(spacing: Spacing.smd) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(group.tagColor.primaryColor)
                                Text(group.name)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTag(group) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showingGroupCreation = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Add group")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }

                Section("Data") {
                    Button {
                        appState.showingExport = true
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.brandPrimary)
                            Text("Export your expenses")
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }

                Section("iCloud") {
                    HStack {
                        Image(systemName: appState.isOffline ? "wifi.slash" : "checkmark.icloud")
                            .foregroundStyle(appState.isOffline ? Color.danger : Color.success)

                        if appState.isOffline {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud unavailable")
                                    .foregroundStyle(Color.textPrimary)
                                Text("Data saved locally")
                                    .font(Fonts.caption(12))
                                    .foregroundStyle(Color.textMuted)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud Sync")
                                    .foregroundStyle(Color.textPrimary)
                                if let lastSync = syncEngine.lastSyncDate {
                                    Text("Last backup \(lastSync, format: .relative(presentation: .named))")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                } else {
                                    Text("Waiting for first sync...")
                                        .font(Fonts.caption(12))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        Spacer()
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(Color.textMuted)
                    }

                    if let privacyURL = URL(string: "https://tally.app/privacy") {
                        Link(destination: privacyURL) {
                            HStack {
                                Text("Privacy Policy")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }

                    if let termsURL = URL(string: "https://tally.app/terms") {
                        Link(destination: termsURL) {
                            HStack {
                                Text("Terms of Service")
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerSheet(selectedCode: Binding(
                    get: { appState.defaultCurrency },
                    set: { appState.defaultCurrency = $0 }
                ))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .presentCustomerCenter(isPresented: $showingCustomerCenter) {
                showingCustomerCenter = false
                Task { await SubscriptionService.refreshProStatus(appState: appState) }
            }
            .sheet(isPresented: $showingTagCreation) {
                TagCreationView()
            }
            .sheet(isPresented: $showingGroupCreation) {
                TagCreationView(isGroupMode: true)
            }
            .sheet(item: $editingTag) { tag in
                TagCreationView(editingTag: tag)
            }
        }
    }

    private func deleteTag(_ tag: TagModel) {
        appState.removeFilter(id: tag.id)

        if tag.isGroup {
            for child in childrenOf(tag) {
                appState.removeFilter(id: child.id)
                child.parentId = nil
            }
        }
        modelContext.delete(tag)
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[Tally] ERROR deleting tag: \(error)")
            #endif
        }
    }
}
