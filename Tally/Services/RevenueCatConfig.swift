import Foundation

enum RevenueCatConfig {
    static let apiKey = "appl_CcfSPdDoUacZCiFzewTHuagDmQy"
    static let proEntitlementId = "A Simple Life - Tally Pro"
    static let offeringIdentifier = "Tally Pro"

    // ─────────────────────────────────────────────────────────────
    // DEBUG PRO OVERRIDE
    // Flip forcePro to toggle Pro mode instantly in DEBUG builds.
    // Zero effect in release/production builds — compiled out entirely.
    //
    // Pro gates controlled by this flag (all read appState.isPro):
    //   • Banner ads removed (HomeView, AddExpenseView, ExpenseDetailView)
    //   • Monthly expense cap (15/month) bypassed
    //   • Monthly export cap bypassed
    //   • Pro-only export templates unlocked (Accountant, Reimbursement, PDF)
    //   • OCR merchant + notes autofill unlocked
    //   • Upsell prompts hidden (3rd/6th/9th expense, OCR banner, monthly limit sheet)
    //   • Settings: Go Pro row replaced with Manage Subscription
    // ─────────────────────────────────────────────────────────────
    #if DEBUG
    static let forcePro: Bool = true
    #endif
}
