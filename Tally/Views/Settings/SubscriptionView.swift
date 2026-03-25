import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var products: [Product] = []
    @State private var didLoadProducts = false

    private let productId = SubscriptionService.proProductId

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
            .task { await loadProducts() }
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
            if let product = products.first {
                PrimaryButton(
                    title: "Subscribe for \(product.displayPrice)/month",
                    action: { purchase(product) },
                    isLoading: isPurchasing
                )
            } else if didLoadProducts {
                PrimaryButton(
                    title: "Retry loading",
                    action: { Task { await loadProducts() } }
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

    // MARK: - StoreKit

    private func loadProducts() async {
        didLoadProducts = false
        errorMessage = nil
        do {
            products = try await Product.products(for: [productId])
            didLoadProducts = true
            if products.isEmpty {
                errorMessage = "Subscription not available. Please try again later."
            }
        } catch {
            didLoadProducts = true
            errorMessage = "Unable to load subscription details."
        }
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        errorMessage = nil

        Task {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified:
                        await MainActor.run {
                            SubscriptionService.setSubscriptionActive(true, appState: appState)
                            isPurchasing = false
                            dismiss()
                        }
                    case .unverified:
                        await MainActor.run {
                            errorMessage = "Purchase could not be verified."
                            isPurchasing = false
                        }
                    }
                case .pending:
                    await MainActor.run {
                        errorMessage = "Purchase is pending approval."
                        isPurchasing = false
                    }
                case .userCancelled:
                    await MainActor.run { isPurchasing = false }
                @unknown default:
                    await MainActor.run { isPurchasing = false }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Purchase failed. Please try again."
                    isPurchasing = false
                }
            }
        }
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == productId {
                    await MainActor.run {
                        SubscriptionService.setSubscriptionActive(true, appState: appState)
                        dismiss()
                    }
                    return
                }
            }
            await MainActor.run {
                SubscriptionService.setSubscriptionActive(false, appState: appState)
                errorMessage = "No active subscription found."
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not restore purchases."
            }
        }
    }
}
