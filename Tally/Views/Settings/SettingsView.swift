import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @State private var showingSubscription = false
    @State private var showingFinancialYearPicker = false
    @State private var showingCurrencyPicker = false

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

                    Button {
                        showingFinancialYearPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Financial year start")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(monthName(appState.financialYearStartMonth))
                                .font(Fonts.caption(14))
                                .foregroundStyle(Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
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
            .sheet(isPresented: $showingFinancialYearPicker) {
                NavigationStack {
                    List(1...12, id: \.self) { month in
                        Button {
                            appState.financialYearStartMonth = month
                            showingFinancialYearPicker = false
                        } label: {
                            HStack {
                                Text(monthName(month))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                if appState.financialYearStartMonth == month {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.brandPrimary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Financial year start")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingFinancialYearPicker = false }
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
        }
    }

    private func monthName(_ month: Int) -> String {
        Calendar.current.monthSymbols[month - 1]
    }
}
