import SwiftUI
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

struct ExpenseCard: View {
    let thumbnailImage: Image?
    /// When `true` and `thumbnailImage` is nil, a receipt exists but is still loading.
    let hasReceiptAttachment: Bool
    let iconSystemName: String
    let iconBackground: Color
    let description: String
    let merchant: String?
    let amountCents: Int
    let currency: String
    /// First tag’s display label; `nil` when expense has no tags (no row tag UI).
    let primaryTagLabel: String?
    let primaryTagColor: TagColor?
    let additionalTagCount: Int

    private var displayTitle: String {
        if let merchant = merchant, !merchant.isEmpty {
            return merchant
        }
        return description.isEmpty ? "Expense" : description
    }

    private static let rowHorizontalPadding: CGFloat = Spacing.md
    private static let iconSlot: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(iconBackground)
                    .frame(width: Self.iconSlot, height: Self.iconSlot)
                if let image = thumbnailImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.iconSlot, height: Self.iconSlot)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                } else if hasReceiptAttachment {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.borderColor.opacity(0.28))
                        .frame(width: Self.iconSlot, height: Self.iconSlot)
                } else {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: Self.iconSlot, height: Self.iconSlot)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
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
                    }
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

private struct BannerAdRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView()
        banner.adUnitID = AdManager.bannerAdUnitID
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
                banner.load(GADRequest())
            }
        }
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
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
