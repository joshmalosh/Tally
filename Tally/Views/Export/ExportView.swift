import SwiftUI
import SwiftData

enum ExportFormat {
    case csv, pdf
}

// MARK: - Pro Benefits Card (every 3rd expense upsell)

struct ProBenefitsCard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Get more from Tally")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    benefitRow(icon: "doc.text.viewfinder", text: "Full OCR auto-fill on receipts")
                    benefitRow(icon: "square.and.arrow.up", text: "Unlimited CSV exports")
                    benefitRow(icon: "doc.richtext", text: "PDF reports")
                    benefitRow(icon: "nosign", text: "No ads")
                }
                .padding(.horizontal, Spacing.sm)
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.xl)
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.smd) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(Fonts.body(15))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Pro Feature Sheet

struct ProFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    let featureName: String
    /// True when the user has a monthly allowance and has spent it, as opposed
    /// to the feature being Pro-only. Saying "Pro feature" to someone who just
    /// used their included CSV export tells them it's locked when it isn't.
    var limitReached: Bool = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: limitReached ? "hourglass" : "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text(limitReached ? "Export limit reached" : "Pro Feature")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(limitReached
                     ? "Free plan includes 1 CSV export per month.\nUpgrade to Pro for unlimited exports and PDF reports."
                     : "\(featureName) is available with Tally Pro.\nUnlock unlimited receipt scanning, unlimited exports, PDF reports, and no ads.")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }
}

/// Shown when a free user has spent their monthly receipt-scan allowance.
///
/// Deliberately not framed as a locked feature: scanning worked 10 times this
/// month and manual entry is still fully available. The gate only removes the
/// automatic extraction, never the ability to log an expense.
struct ScanLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSubscription = false

    /// Called when the user chooses to carry on typing it in themselves.
    var onEnterManually: () -> Void = {}

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text("Scan limit reached")
                    .font(Fonts.headline(20))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Free plan includes \(AppState.freeTierOCRScansPerMonth) receipt scans per month.\nYou can still add this expense manually.\nUpgrade to Pro for unlimited scanning.")
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.smd) {
                PrimaryButton(title: "Upgrade to Pro") {
                    showingSubscription = true
                }

                Button {
                    onEnterManually()
                    dismiss()
                } label: {
                    Text("Enter manually")
                        .font(Fonts.body(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showingSubscription) {
            SubscriptionView()
        }
    }
}
