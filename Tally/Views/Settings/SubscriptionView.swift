import SwiftUI
import RevenueCat
import RevenueCatUI

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var monthlyPackage: Package?
    @State private var didLoadProducts = false
    @State private var presentingCustomerCenter = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.isPro {
                    proSubscriberContent
                } else {
                    freeTierContent
                }
            }
            .navigationTitle(appState.isPro ? "Subscription" : "Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .task {
                if !appState.isPro {
                    await loadMonthlyPackage()
                }
            }
        }
        .presentCustomerCenter(isPresented: $presentingCustomerCenter) {
            presentingCustomerCenter = false
        }
    }

    // MARK: - Pro (manage)

    private var proSubscriberContent: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.brandPrimary)

                    Text("Tally Pro")
                        .font(Fonts.title(22))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Manage billing, plans, and restores from RevenueCat Customer Center.")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(title: "Manage subscription") {
                    presentingCustomerCenter = true
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.surface)
    }

    // MARK: - Free (Go Pro — unchanged layout)

    private var freeTierContent: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                heroSection
                featuresSection
                pricingSection
                legalSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.surface)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandPrimary)

            Text("Unlock Tally Pro")
                .font(Fonts.title(22))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text("Everything you need to track expenses like a pro.")
                .font(Fonts.body(15))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: Spacing.md) {
            featureRow(icon: "tablecells", text: "Unlimited CSV exports")
            featureRow(icon: "doc.richtext", text: "PDF export")
            featureRow(icon: "calendar.badge.clock", text: "Monthly auto-export")
            featureRow(icon: "text.viewfinder", text: "OCR auto-fill from receipts")
            featureRow(icon: "line.3.horizontal.decrease.circle", text: "Advanced filters")
            featureRow(icon: "eye.slash.fill", text: "No ads, ever")
        }
        .padding(Spacing.lg)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 28)
            Text(text)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: Spacing.md) {
            if let package = monthlyPackage {
                PrimaryButton(
                    title: "Subscribe for \(package.localizedPriceString)/month",
                    action: { purchase(package: package) },
                    isLoading: isPurchasing
                )
            } else if didLoadProducts {
                PrimaryButton(
                    title: "Retry loading",
                    action: { Task { await loadMonthlyPackage() } }
                )
            } else {
                PrimaryButton(
                    title: "Loading...",
                    action: {},
                    isLoading: true
                )
            }

            Button("Restore purchases") {
                Task { await restorePurchases() }
            }
            .font(Fonts.body(14))
            .foregroundStyle(Color.brandPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(Fonts.caption(13))
                    .foregroundStyle(Color.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
            .font(Fonts.caption(11))
            .foregroundStyle(Color.textMuted)
            .multilineTextAlignment(.center)
    }

    // MARK: - RevenueCat

    private func loadMonthlyPackage() async {
        didLoadProducts = false
        errorMessage = nil
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.offering(identifier: RevenueCatConfig.offeringIdentifier)
            guard let offering else {
                await MainActor.run {
                    didLoadProducts = true
                    monthlyPackage = nil
                    errorMessage = "Subscription not available. Please try again later."
                }
                return
            }
            let pkg = offering.package(identifier: "$rc_monthly") ?? offering.availablePackages.first
            await MainActor.run {
                monthlyPackage = pkg
                didLoadProducts = true
                if pkg == nil {
                    errorMessage = "Subscription not available. Please try again later."
                }
            }
        } catch {
            await MainActor.run {
                didLoadProducts = true
                monthlyPackage = nil
                errorMessage = "Unable to load subscription details."
            }
        }
    }

    private func purchase(package: Package) {
        isPurchasing = true
        errorMessage = nil

        Task {
            do {
                let result = try await Purchases.shared.purchase(package: package)
                await MainActor.run {
                    isPurchasing = false
                    if result.userCancelled {
                        dismiss()
                        return
                    }
                    let active = result.customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true
                    if active {
                        appState.subscriptionStatus = .pro
                        dismiss()
                    } else {
                        errorMessage = "Purchase could not be verified."
                    }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    if let code = error as? ErrorCode, code == .purchaseCancelledError {
                        dismiss()
                        return
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func restorePurchases() async {
        errorMessage = nil
        do {
            _ = try await Purchases.shared.restorePurchases()
            await SubscriptionService.refreshProStatus(appState: appState)
            await MainActor.run {
                if appState.isPro {
                    dismiss()
                } else {
                    errorMessage = "No active subscription found."
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}
