import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var packages: [Package] = []
    @State private var didLoadPackages = false

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .task { await loadPackages() }
        }
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
            if let package = packages.first {
                let priceText = package.storeProduct.localizedPriceString
                PrimaryButton(
                    title: "Subscribe for \(priceText)/month",
                    action: { purchase(package) },
                    isLoading: isPurchasing
                )
            } else if didLoadPackages {
                PrimaryButton(
                    title: "Retry loading",
                    action: { Task { await loadPackages() } }
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

    private func loadPackages() async {
        didLoadPackages = false
        errorMessage = nil
        do {
            let offerings = try await Purchases.shared.offerings()
            let availablePackages = offerings[RevenueCatConfig.offeringIdentifier]?.availablePackages ?? []
            let monthlyFirst = availablePackages.sorted { p1, p2 in
                if p1.packageType == .monthly { return true }
                if p2.packageType == .monthly { return false }
                return true
            }
            await MainActor.run {
                packages = monthlyFirst
                didLoadPackages = true
                if packages.isEmpty {
                    errorMessage = "Subscription not available. Please try again later."
                }
            }
        } catch {
            await MainActor.run {
                didLoadPackages = true
                errorMessage = "Unable to load subscription details."
            }
        }
    }

    private func purchase(_ package: Package) {
        isPurchasing = true
        errorMessage = nil

        Task {
            do {
                let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
                await MainActor.run {
                    isPurchasing = false
                    if userCancelled { return }
                    if customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true {
                        appState.subscriptionStatus = .pro
                        dismiss()
                    } else {
                        errorMessage = "Purchase could not be verified."
                    }
                }
            } catch let error as ErrorCode where error == .purchaseCancelledError {
                await MainActor.run { isPurchasing = false }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = "Purchase failed. Please try again."
                }
            }
        }
    }

    private func restorePurchases() async {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await MainActor.run {
                if customerInfo.entitlements[RevenueCatConfig.proEntitlementId]?.isActive == true {
                    appState.subscriptionStatus = .pro
                    dismiss()
                } else {
                    errorMessage = "No active subscription found."
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not restore purchases."
            }
        }
    }
}
