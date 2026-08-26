import SwiftUI
import OSLog
import UIKit
import GoogleMobileAds

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(title)
                        .font(Fonts.headline(16))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(configuration.isPressed ? Color.brandPressed : Color.brandPrimary)
            )
    }
}

// MARK: - SecondaryButton

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.brandPrimary))
                } else {
                    Text(title)
                        .font(Fonts.headline(16))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.brandPrimary, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isLoading)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - ChipView (text pill)

struct ChipView: View {
    let label: String
    let isActive: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.chipActiveText : Color.chipInactiveText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill)
                    .fill(isActive ? Color.chipActiveBg : Color.chipInactiveBg)
            )
    }
}

// MARK: - TagPill (neutral filter chip — no colored backgrounds)

struct TagPill: View {
    let name: String
    let tagColor: TagColor
    let isActive: Bool
    var isGroup: Bool = false
    var isExpanded: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))

            if isGroup {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
        }
        .foregroundStyle(isActive ? Color.chipActiveText : Color.chipInactiveText)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: Radius.pill)
                .fill(isActive ? Color.chipActiveBg : Color.chipInactiveBg)
        )
    }
}

// MARK: - AddTagPill

struct AddTagPill: View {
    var body: some View {
        Text("+ Tag or Group")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill)
                    .stroke(Color.borderColor, lineWidth: 1)
            )
    }
}

// MARK: - ExpenseCard

/// Self-loading receipt thumbnail. Each instance owns its image state and
/// loads on appear via its own `.task`, re-rendering itself when the image
/// arrives — so List cells refresh reliably instead of depending on a global
/// version bump (which left thumbnails "hit or miss" until you scrolled).
struct ReceiptThumbnailView: View {
    let cacheKey: String
    let attachmentKey: String?
    let attachmentData: Data?
    var size: CGFloat = 38
    var cornerRadius: CGFloat = Radius.sm

    @State private var image: UIImage?

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 250
        return c
    }()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.borderColor.opacity(0.28))
                    .frame(width: size, height: size)
            }
        }
        .task(id: cacheKey) { await load() }
    }

    private func load() async {
        if let cached = Self.cache.object(forKey: cacheKey as NSString) {
            image = cached
            return
        }
        let key = attachmentKey
        let data = attachmentData
        let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
            if let key {
                if let thumb = AttachmentService.shared.loadThumbnail(key: key) { return thumb }
                // Thumbnail file missing — rebuild from the stored attachment and persist.
                if let d = AttachmentService.shared.loadImageData(key: key),
                   let thumb = AttachmentService.downsampledThumbnail(from: d) {
                    await AttachmentService.shared.saveThumbnail(thumb, key: key)
                    return thumb
                }
            }
            if let data {
                return AttachmentService.downsampledThumbnail(from: data) ?? UIImage(data: data)
            }
            return nil
        }.value
        if let loaded {
            Self.cache.setObject(loaded, forKey: cacheKey as NSString)
            image = loaded
        }
    }
}

struct ExpenseCard: View {
    /// Receipt attachment identity for the self-loading thumbnail (nil = no receipt).
    let receiptCacheKey: String?
    let receiptAttachmentKey: String?
    let receiptAttachmentData: Data?
    /// When set, the icon slot shows this emoji (a tag's chosen emoji) instead of
    /// the SF Symbol. Falls back to `iconSystemName` when nil (e.g. untagged).
    var iconEmoji: String? = nil
    let iconSystemName: String
    let iconBackground: Color
    let description: String
    let merchant: String?
    /// User’s free-text note; shown as the row heading when present.
    let notes: String?
    let amountCents: Int
    let currency: String
    /// First tag’s display label; `nil` when expense has no tags (no row tag UI).
    let primaryTagLabel: String?
    let primaryTagColor: TagColor?
    let additionalTagCount: Int

    /// "What" — merchant first, then notes, then description, then fallback.
    private var displayTitle: String {
        if let m = merchant, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return m.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let n = notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return n.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !description.isEmpty { return description }
        return "Expense"
    }

    /// Secondary context line — note when merchant is the heading, merchant when note is the heading.
    private var displaySubtitle: String? {
        let m = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !m.isEmpty { return n.isEmpty ? nil : n }   // merchant is title → show note
        if !n.isEmpty { return m.isEmpty ? nil : m }   // note is title → show merchant
        return nil
    }

    private static let rowHorizontalPadding: CGFloat = Spacing.md
    private static let iconSlot: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(iconBackground)
                    .frame(width: Self.iconSlot, height: Self.iconSlot)
                if let cacheKey = receiptCacheKey {
                    ReceiptThumbnailView(
                        cacheKey: cacheKey,
                        attachmentKey: receiptAttachmentKey,
                        attachmentData: receiptAttachmentData,
                        size: Self.iconSlot,
                        cornerRadius: Radius.sm
                    )
                } else if let iconEmoji {
                    Text(iconEmoji)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: Self.iconSlot, height: Self.iconSlot)

            VStack(alignment: .leading, spacing: 4) {
                // Heading: What
                Text(displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Tag pill row
                if let label = primaryTagLabel, let tagColor = primaryTagColor {
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tagColor.primaryColor)
                                .frame(width: 7, height: 7)
                            Text(label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tagColor.primaryColor.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tagColor.primaryColor.opacity(0.1))
                        .clipShape(Capsule())

                        if additionalTagCount > 0 {
                            Text("+\(additionalTagCount)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }

                        // Secondary context after tag — note if merchant is heading, else nothing
                        if let sub = displaySubtitle {
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textMuted)
                            Text(sub)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                        }
                    }
                } else if let sub = displaySubtitle {
                    // No tag — show secondary context on its own line
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(CurrencyFormatter.shared.format(cents: amountCents, currencyCode: currency))
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, 13)
    }
}

// MARK: - FABButton

struct FABButton: View {
    let action: () -> Void
    @State private var didTap = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    private var fabSize: CGFloat { 75 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.actionGreen, lineWidth: 2)
                .frame(width: fabSize, height: fabSize)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                    didTap = true
                }
                pulseOpacity = 0.5
                pulseScale = 1.0
                withAnimation(.easeOut(duration: 0.5)) {
                    pulseScale = 1.8
                    pulseOpacity = 0.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        didTap = false
                    }
                }

                action()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: fabSize, height: fabSize)
            }
            .buttonStyle(FABButtonStyle())
            .scaleEffect(didTap ? 0.88 : 1.0)
        }
    }
}

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.actionGreenPressed : Color.actionGreen)
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.12), radius: configuration.isPressed ? 3 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Fonts.headline(18))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Fonts.body(15))
                    .foregroundStyle(Color.textBody)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
            }
        }
    }
}

// MARK: - BannerAdView

struct BannerAdView: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderColor)
                .frame(height: 1)
            BannerAdRepresentable()
                .frame(height: 50)
                .background(Color.surface)
        }
    }
}

/// A banner plus an "upgrade to remove ads" caption. Free tier only — renders
/// nothing for Pro. Reused in the expense list, reports, and period detail.
struct InlineUpgradeAd: View {
    @Environment(AdManager.self) private var adManager
    @Environment(AppState.self) private var appState

    var body: some View {
        if adManager.shouldShowBannerAd {
            VStack(spacing: 6) {
                BannerAdView()
                Button {
                    appState.showingSubscription = true
                } label: {
                    Text("Get ad-free expenses in premium - ")
                        .foregroundColor(Color(hex: "8F9E94"))
                    + Text("upgrade now")
                        .foregroundColor(Color.brandPrimary)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView()
        banner.adUnitID = AdManager.bannerAdUnitID
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = .clear

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
               let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController {
                banner.rootViewController = rootVC
                let viewWidth = rootVC.view.frame.inset(by: rootVC.view.safeAreaInsets).width
                banner.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(viewWidth)
                Log.ads.debug("loading banner width=\(viewWidth, privacy: .public)")
                banner.load(GADRequest())
            } else {
                Log.ads.error("no rootViewController — banner not loaded")
            }
        }
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}

    final class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            Log.ads.debug("banner received ad")
        }
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            Log.ads.error("banner failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowAlignment: VerticalAlignment = .top
    var centerRows: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var rows: [[Int]] = [[]]
        var rowHeights: [CGFloat] = [0]
        var rowWidths: [CGFloat] = [0]
        var x: CGFloat = 0
        var y: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeights[rowHeights.count - 1] + spacing
                rows.append([])
                rowHeights.append(0)
                rowWidths.append(0)
            }

            positions.append(CGPoint(x: x, y: y))
            rows[rows.count - 1].append(index)
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            x += size.width + spacing
            rowWidths[rowWidths.count - 1] = x - spacing
        }

        let totalWidth = rowWidths.max() ?? 0

        if rowAlignment == .bottom || centerRows {
            for (rowIndex, indices) in rows.enumerated() {
                let rh = rowHeights[rowIndex]
                let rw = rowWidths[rowIndex]
                let horizontalOffset = centerRows ? (totalWidth - rw) / 2 : 0

                for i in indices {
                    let verticalOffset: CGFloat
                    switch rowAlignment {
                    case .bottom:
                        verticalOffset = rh - sizes[i].height
                    case .center:
                        verticalOffset = (rh - sizes[i].height) / 2
                    default:
                        verticalOffset = 0
                    }
                    positions[i].x += horizontalOffset
                    positions[i].y += verticalOffset
                }
            }
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: y + (rowHeights.last ?? 0)),
            positions: positions
        )
    }
}

// MARK: - TallySuggestsCard

/// Shared "Tally Suggests" banner shown in both AddExpenseView and ExpenseDetailView.
/// Callers gate visibility with their own `if let suggestion … { TallySuggestsCard(…) }` block.
struct TallySuggestsCard: View {
    let suggestion: TagSuggestionEngine.Suggestion
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "2F402E"))
                Text("TALLY SUGGESTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "2F402E"))
                    .tracking(0.8)
            }

            Text("Looks like a \(suggestion.reason) — want to tag this as **\(suggestion.tag.name)**?")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "2F402E").opacity(0.9))

            HStack(spacing: 10) {
                Button(action: onApply) {
                    Text("Apply tag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(Color(hex: "2F402E"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "2F402E"))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(Color(hex: "2F402E").opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "EAF5EC"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "2F402E").opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

// MARK: - Expense celebration: confetti burst + monthly total toast

private struct ConfettiParticleData: Identifiable {
    let id: Int
    let color: Color
    let dx: CGFloat
    let dy: CGFloat
    let rotation: Double
    let delay: Double
}

private struct ConfettiParticleView: View {
    let data: ConfettiParticleData
    let origin: CGPoint

    @State private var launched = false
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(data.color)
            .frame(width: 8, height: 8)
            .scaleEffect(launched ? 1.0 : 0.4)
            .rotationEffect(.degrees(launched ? data.rotation : 0))
            .opacity(visible ? 1.0 : 0.0)
            .position(
                x: launched ? origin.x + data.dx : origin.x,
                y: launched ? origin.y + data.dy : origin.y
            )
            .task {
                try? await Task.sleep(nanoseconds: UInt64(data.delay * 1_000_000_000))
                withAnimation(.linear(duration: 0.11)) { visible = true }
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1)) { launched = true }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.linear(duration: 0.99)) { visible = false }
            }
    }
}

struct ExpenseCelebrationView: View {
    let amountCents: Int
    let currency: String
    let monthlyTotalCents: Int

    @State private var particles: [ConfettiParticleData] = {
        let colors: [Color] = [
            Color(hex: "C27040"),  // terracotta  ~ oklch(0.7 0.15 30)
            Color(hex: "4A8A6A"),  // sage        ~ oklch(0.6 0.12 150)
            Color(hex: "C4A030"),  // gold        ~ oklch(0.75 0.15 70)
        ]
        return (0..<14).map { i in
            let angleDeg = Double.random(in: -165...165)
            let angle = angleDeg * .pi / 180
            let distance = CGFloat.random(in: 80...160)
            return ConfettiParticleData(
                id: i,
                color: colors[i % 3],
                dx: distance * CGFloat(sin(angle)),
                dy: -distance * abs(CGFloat(cos(angle))),
                rotation: Double.random(in: -270...270),
                delay: Double(i) * 0.018
            )
        }
    }()

    @State private var showToast = false

    private var symbol: String { CurrencyFormatter.shared.symbol(for: currency) }
    private var usesDecimals: Bool { CurrencyFormatter.shared.usesDecimals(for: currency) }

    private func fmt(_ cents: Int) -> String {
        usesDecimals
            ? "\(symbol)\(String(format: "%.2f", Double(cents) / 100))"
            : "\(symbol)\(cents)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Confetti burst — origin sits above the save button area
            GeometryReader { geo in
                let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height - 90)
                ForEach(particles) { p in
                    ConfettiParticleView(data: p, origin: origin)
                }
            }
            .allowsHitTesting(false)

            // Monthly total toast
            if showToast {
                toastView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.45)) {
                showToast = true
            }
        }
    }

    private var toastView: some View {
        HStack(spacing: 12) {
            // Checkmark badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "8FA893").opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "8FA893"))
            }

            // Label + amounts
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS MONTH")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(fmt(monthlyTotalCents))
                        .font(.system(size: 19, weight: .semibold).italic())
                        .foregroundStyle(Color.white)
                    Text("+\(fmt(amountCents))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            Spacer(minLength: 0)

            // Sparkline — points from Lovable spec
            Canvas { ctx, size in
                let raw: [(CGFloat, CGFloat)] = [
                    (1,16),(8,12),(15,14),(22,8),(29,10),(36,5),(45,3)
                ]
                var path = Path()
                for (i, (x, y)) in raw.enumerated() {
                    let pt = CGPoint(x: x * size.width / 46, y: y * size.height / 22)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(Color(hex: "8FA893")),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 46, height: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(hex: "2F402E"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

// MARK: - HomeToggle

/// Branded "show on home screen" switch: a white thumb on the left when off,
/// a green thumb with a white house glyph on the right when on. Used anywhere
/// a tag or group's `showOnHome` flag can be flipped (tags list, edit sheet).
struct HomeToggle: View {
    let isOn: Bool
    let onToggle: () -> Void

    private let width: CGFloat = 60
    private let height: CGFloat = 34
    private let thumbSize: CGFloat = 28

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // Track fills brand green when on, like a native iOS toggle, so an
                // active tag reads at a glance.
                Capsule()
                    .fill(isOn ? Color.brandPrimary : Color(hex: "EDEAE2"))
                    .overlay(Capsule().stroke(isOn ? Color.clear : Color.borderColor, lineWidth: 1))
                    .frame(width: width, height: height)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: "house.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary)
                            .opacity(isOn ? 1 : 0)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 0.5)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .accessibilityLabel("Show on home screen")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - TagIconBadge (shared circular colour swatch + emoji)

/// The tag/group icon used across the Tags tab, the pin-to-home sheet and the
/// filter sheet — one definition so those three lists can't drift apart.
struct TagIconBadge: View {
    let tag: TagModel
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(tag.tagColor.primaryColor)
                .frame(width: size, height: size)
            Text(tag.displayEmoji)
                .font(.system(size: size * 0.5))
        }
    }
}

// MARK: - FilterRow (shared selection row: filter sheet, tag picker)

/// A full-width, full-height tappable filter row: the entire row (not just the
/// glyphs) is a hit target, and pressing it flashes the brand green with white
/// text/checkmark so a press always reads as a press.
///
/// Implemented as a real Button so it never steals scroll gestures inside a
/// ScrollView (a zero-distance DragGesture does); the pressed state reaches
/// the label through the environment.
struct FilterRow<Leading: View>: View {
    let title: String
    var titleFont: Font = .system(size: 16)
    var titleColor: Color = Color(hex: "1C1C1E")
    let isSelected: Bool
    var checkmarkFont: Font = .system(size: 14, weight: .semibold)
    var horizontalPadding: CGFloat = 20
    var verticalPadding: CGFloat = 13
    let leading: () -> Leading
    let action: () -> Void

    init(
        title: String,
        titleFont: Font = .system(size: 16),
        titleColor: Color = Color(hex: "1C1C1E"),
        isSelected: Bool,
        checkmarkFont: Font = .system(size: 14, weight: .semibold),
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 13,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.isSelected = isSelected
        self.checkmarkFont = checkmarkFont
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.leading = leading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            FilterRowLabel(
                title: title,
                titleFont: titleFont,
                titleColor: titleColor,
                isSelected: isSelected,
                checkmarkFont: checkmarkFont,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                leading: leading
            )
        }
        .buttonStyle(FilterRowPressStyle())
    }
}

private struct FilterRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var filterRowPressed: Bool {
        get { self[FilterRowPressedKey.self] }
        set { self[FilterRowPressedKey.self] = newValue }
    }
}

private struct FilterRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.filterRowPressed, configuration.isPressed)
    }
}

private struct FilterRowLabel<Leading: View>: View {
    @Environment(\.filterRowPressed) private var isPressed

    let title: String
    let titleFont: Font
    let titleColor: Color
    let isSelected: Bool
    let checkmarkFont: Font
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let leading: () -> Leading

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Text(title)
                .font(titleFont)
                .foregroundStyle(isPressed ? Color.white : titleColor)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(checkmarkFont)
                    .foregroundStyle(isPressed ? Color.white : Color(hex: "2F402E"))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
        .background(isPressed ? Color.brandPrimary : Color.clear)
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}

// MARK: - ExpenseShredView (delete animation)

/// A small receipt (tilted 35°) shredding down toward the base of the screen,
/// with white particles puffing up. Sits behind the FAB and tab bar. Lives
/// ~1.6s; the host hides it shortly after. Mirrors the add-expense confetti in
/// scale and spirit — a satisfying counterpart for deletion.
struct ExpenseShredView: View {
    @State private var animate = false
    // Oscillates between -amp and +amp to shake the receipt; also feeds a small
    // rotation wobble. Driven by a repeating auto-reversing withAnimation, which
    // fires reliably on appear (keyframeAnimator did not on device).
    @State private var shake: CGFloat = 0
    private let shakeAmp: CGFloat = 1.25

    private struct Strip: Identifiable {
        let id: Int
        let xOffset: CGFloat
        let width: CGFloat
        let fall: CGFloat
        let rotation: Double
        let delay: Double
    }
    private struct Spark: Identifiable {
        let id: Int
        let dx: CGFloat
        let rise: CGFloat
        let size: CGFloat
        let delay: Double
    }

    private let receiptWidth: CGFloat = 46
    private let receiptHeight: CGFloat = 58
    private let strips: [Strip]
    private let sparks: [Spark]

    init() {
        let count = 9
        strips = (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            return Strip(
                id: i,
                xOffset: (t - 0.5) * (Self.receiptWidthStatic - 4),
                width: 3.5,
                fall: 102 + CGFloat.random(in: 0...40),
                rotation: Double.random(in: -55...55),
                delay: Double(i) * 0.02
            )
        }
        sparks = (0..<12).map { i in
            Spark(
                id: i,
                dx: CGFloat.random(in: -32...32),
                rise: CGFloat.random(in: 42...92),
                size: CGFloat.random(in: 3...6),
                delay: Double.random(in: 0...0.22)
            )
        }
    }

    private static let receiptWidthStatic: CGFloat = 46

    // Distance from the physical bottom to the shred line — sits over the
    // tab-bar / FAB zone. No GeometryReader: bottom alignment + padding places
    // everything deterministically, immune to the parent's constant re-renders
    // (thumbnail bumps, list changes) that made the geometry-based version jump.
    private let bottomInset: CGFloat = 88

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            // Receipt (tilted 20° left) lowered straight down and faded.
            // `shake` drives ONLY the rotation (a subtle left-right rock). The
            // lower is a SEPARATE y-offset — combining shake-x and lower-y in one
            // .offset let the fast repeating shake animation bleed into the y and
            // jerk the receipt vertically.
            receiptBody
                .frame(width: receiptWidth, height: receiptHeight)
                .rotationEffect(.degrees(-20 + Double(shake)), anchor: .bottom)
                .offset(y: animate ? 84 : 0)
                .opacity(animate ? 0 : 1)
                .padding(.bottom, bottomInset)

            // Shredded strips falling from the base line.
            ForEach(strips) { s in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
                    )
                    .frame(width: s.width, height: 13)
                    .rotationEffect(.degrees(animate ? s.rotation : 0))
                    .offset(x: s.xOffset, y: animate ? s.fall : -2)
                    .opacity(animate ? 0 : 1)
                    .padding(.bottom, bottomInset)
                    .animation(.easeIn(duration: 1.15).delay(s.delay), value: animate)
            }

            // White sparks shooting up from the base.
            ForEach(sparks) { p in
                Circle()
                    .fill(Color.white)
                    .frame(width: p.size, height: p.size)
                    .offset(x: animate ? p.dx : 0, y: animate ? -p.rise : 0)
                    .opacity(animate ? 0 : 1)
                    .padding(.bottom, bottomInset)
                    .animation(.easeOut(duration: 0.8).delay(p.delay), value: animate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Lower + fade (drives receipt offset/opacity and the strips/sparks).
            withAnimation(.easeIn(duration: 0.9)) { animate = true }
            // Shake: start at -amp, oscillate to +amp and back a few times.
            shake = -shakeAmp
            withAnimation(.easeInOut(duration: 0.13).repeatCount(6, autoreverses: true)) {
                shake = shakeAmp
            }
        }
    }

    private var receiptBody: some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(hex: "DEDAD2"))
                    .frame(height: 3)
                    .padding(.horizontal, 7)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(hex: "DEDAD2"), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 3)
    }
}
