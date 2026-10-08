import SwiftUI
import SwiftData
import UIKit

// MARK: - SF Symbol mapping for default system tags

enum TagSymbolMap {
    static func symbol(for tagName: String) -> String {
        switch tagName {
        case "Groceries":           return "cart.fill"
        case "Dining & Takeaway":   return "fork.knife"
        case "Transport":           return "car.fill"
        case "Home":                return "house.fill"
        case "Shopping":            return "bag.fill"
        case "Subscriptions":       return "creditcard.fill"
        case "Health & Fitness":    return "heart.fill"
        case "Travel":              return "airplane"
        case "Work":                return "briefcase.fill"
        case "Entertainment":       return "ticket.fill"
        case "Bills & Utilities":   return "bolt.fill"
        case "Gifts & Donations":   return "gift.fill"
        case "Education":           return "book.fill"
        case "Other":               return "ellipsis.circle.fill"
        default:                    return "tag.fill"
        }
    }
}

// MARK: - Home Tag Bar

struct HomeTagBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil })
    private var activeExpenses: [ExpenseModel]
    @Binding var selectedTagId: String?
    @State private var showingAddSheet = false
    @State private var editingTag: TagModel?
    // Drive the green scroll-position bar under the tag row.
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    // Home-screen-style edit mode: long-press a pinned tag to make the row jiggle,
    // then drag to reorder or tap the ⊖ badge to unpin. `orderedHomeIds` is the live
    // display order during a drag; `draggingId`/`dragTranslation` float the held card.
    @State private var isEditing = false
    @State private var orderedHomeIds: [String] = []
    @State private var draggingId: String?
    @State private var dragTranslation: CGFloat = 0

    /// One pinned card plus the row spacing — the reorder stride.
    private let cardStride: CGFloat = 89 + 8

    private var currency: String { appState.activeCurrency }

    private var homeTags: [TagModel] {
        allTags.filter { $0.showOnHome && !$0.isGroup }
            .sorted {
                if $0.homeSortOrder != $1.homeSortOrder { return $0.homeSortOrder < $1.homeSortOrder }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Live display order — the reordered ids while editing, else `homeTags`.
    private var displayTags: [TagModel] {
        guard isEditing, !orderedHomeIds.isEmpty else { return homeTags }
        let byId = Dictionary(uniqueKeysWithValues: homeTags.map { ($0.id, $0) })
        let ordered = orderedHomeIds.compactMap { byId[$0] }
        let extra = homeTags.filter { t in !orderedHomeIds.contains(t.id) }
        return ordered + extra
    }

    /// Sum of this year's expenses for a given tag ID.
    private func yearlyTotal(for tagId: String) -> Int {
        let cal = Calendar.current
        let now = Date()
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now
        return activeExpenses
            .filter { $0.date >= yearStart && $0.date <= now }
            .filter { $0.currency == currency }
            .filter { $0.resolvedTagIds.contains(tagId) }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// Sum of this year's expenses across all tags, in the default currency only
    /// — summing mixed currencies without a rate produces a meaningless total.
    private var yearlyTotalAll: Int {
        let cal = Calendar.current
        let now = Date()
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now
        return activeExpenses
            .filter { $0.date >= yearStart && $0.date <= now }
            .filter { $0.currency == currency }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// A small green bar under the tag row that tracks scroll position, so a user
    /// with more pinned tags than fit on screen can see the row scrolls. Hidden
    /// when the row already fits.
    @ViewBuilder
    private var tagScrollIndicator: some View {
        let overflow = contentWidth - viewportWidth
        if overflow > 1, viewportWidth > 0 {
            let trackWidth = max(0, viewportWidth - 32)
            let baseThumb = max(28, trackWidth * (viewportWidth / contentWidth))
            // Rubber-band: overscrolling past either end squeezes the thumb against
            // that edge, the way the native iOS scroll indicator behaves. Bounce
            // drives scrollOffset below 0 / above overflow, and we compress from there.
            let overStart = max(0, -scrollOffset)
            let overEnd = max(0, scrollOffset - overflow)
            let thumbWidth = max(16, baseThumb - min(baseThumb - 16, (overStart + overEnd) * 0.7))
            let frac = min(1, max(0, scrollOffset / overflow))
            let thumbX: CGFloat = overStart > 0 ? 0
                : (overEnd > 0 ? (trackWidth - thumbWidth)
                   : (trackWidth - baseThumb) * frac)
            ZStack(alignment: .leading) {
                // Minimal moss hairline: mid-moss track, soft dark-moss thumb.
                Capsule()
                    .fill(Color(hex: "4A5E50").opacity(0.2))
                    .frame(width: trackWidth, height: 2.5)
                Capsule()
                    .fill(Color.brandPrimary.opacity(0.6))
                    .frame(width: thumbWidth, height: 2.5)
                    .offset(x: thumbX)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" card — always first
                TagFilterCard(
                    icon: "square.grid.2x2",
                    label: "All",
                    amountCents: yearlyTotalAll,
                    currency: currency,
                    iconBg: Color(hex: "E8F0EA"),
                    iconColor: Color(hex: "346049"),
                    tint: Color(hex: "346049"),
                    isSelected: selectedTagId == nil
                ) {
                    // While editing, the always-visible All card doubles as an exit,
                    // in case many pins push the Done card past the row's edge.
                    if isEditing { exitEditMode(); return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTagId = nil }
                }

                // Tag cards
                ForEach(Array(displayTags.enumerated()), id: \.element.id) { index, tag in
                    pinnedCard(tag, index: index)
                }

                // Trailing control: "Pin tag" normally, "Done" while editing.
                if isEditing {
                    DoneEditingCard { exitEditMode() }
                } else {
                    MoreTagCard {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingAddSheet = true
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            // KVO on the underlying UIScrollView — SwiftUI preferences didn't fire
            // reliably from inside the scroll content (same reason the list uses a
            // KVO detector). Reports offset + content/viewport widths for the bar.
            .background(
                HorizontalScrollObserver { offsetX, contentW, viewportW in
                    scrollOffset = offsetX
                    contentWidth = contentW
                    viewportWidth = viewportW
                }
            )
        }
        .scrollDisabled(isEditing)   // drags reorder instead of scrolling while editing

        if !isEditing { tagScrollIndicator }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddToHomeBarSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTag) { tag in
            TagCreationView(editingTag: tag)
        }
    }

    // MARK: - Pinned card (edit-mode jiggle / reorder / unpin)

    @ViewBuilder
    private func pinnedCard(_ tag: TagModel, index: Int) -> some View {
        let symbol = tag.symbolName ?? tag.icon ?? TagSymbolMap.symbol(for: tag.name)
        let primary = tag.tagColor.primaryColor
        let isDragging = draggingId == tag.id

        ZStack(alignment: .topLeading) {
            TagFilterCard(
                icon: symbol,
                iconEmoji: tag.displayEmoji,
                label: tag.name,
                amountCents: yearlyTotal(for: tag.id),
                currency: currency,
                iconBg: primary,
                iconColor: primary,
                tint: primary,
                isSelected: selectedTagId == tag.id,
                // Long-press enters edit mode (jiggle), like the iOS Home Screen.
                onLongPress: { if !isEditing { enterEditMode() } }
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTagId = selectedTagId == tag.id ? nil : tag.id
                }
            }
            // While editing, the card's own tap/long-press are off; the wrapper
            // handles tap-to-edit, drag-to-reorder and the unpin badge.
            .allowsHitTesting(!isEditing)

            if isEditing {
                Button { unpin(tag) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 24, height: 24)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
            }
        }
        .modifier(JiggleModifier(active: isEditing, seed: index))
        .offset(x: isDragging ? dragTranslation : reorderOffset(for: tag.id, at: index))
        .zIndex(isDragging ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if isEditing { editingTag = tag } }
        .gesture(isEditing ? reorderDrag(for: tag.id) : nil)
    }

    private func reorderDrag(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if draggingId == nil {
                    draggingId = id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                dragTranslation = value.translation.width
            }
            .onEnded { _ in commitReorder() }
    }

    /// Offset applied to a non-dragged card so it slides open a gap for the held one.
    private func reorderOffset(for id: String, at index: Int) -> CGFloat {
        guard isEditing, let dragging = draggingId, dragging != id,
              let from = displayTags.firstIndex(where: { $0.id == dragging }) else { return 0 }
        let to = targetIndex(from: from)
        if from < to, index > from, index <= to { return -cardStride }
        if from > to, index >= to, index < from { return cardStride }
        return 0
    }

    private func targetIndex(from: Int) -> Int {
        let shift = Int((dragTranslation / cardStride).rounded())
        return min(max(0, from + shift), displayTags.count - 1)
    }

    private func enterEditMode() {
        orderedHomeIds = homeTags.map(\.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
    }

    private func exitEditMode() {
        draggingId = nil
        dragTranslation = 0
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
    }

    private func commitReorder() {
        defer {
            withAnimation(.easeInOut(duration: 0.2)) {
                draggingId = nil
                dragTranslation = 0
            }
        }
        guard let dragging = draggingId,
              let from = displayTags.firstIndex(where: { $0.id == dragging }) else { return }
        let to = targetIndex(from: from)
        var ids = displayTags.map(\.id)
        let moved = ids.remove(at: from)
        ids.insert(moved, at: min(to, ids.count))
        orderedHomeIds = ids
        let byId = Dictionary(uniqueKeysWithValues: homeTags.map { ($0.id, $0) })
        for (i, tagId) in ids.enumerated() { byId[tagId]?.homeSortOrder = i }
        try? modelContext.save()
    }

    private func unpin(_ tag: TagModel) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        tag.showOnHome = false
        try? modelContext.save()
        withAnimation(.easeInOut(duration: 0.2)) {
            orderedHomeIds.removeAll { $0 == tag.id }
        }
        if homeTags.filter({ $0.id != tag.id }).isEmpty { exitEditMode() }
    }
}

// MARK: - iOS-style jiggle

/// A small continuous rotation oscillation, like Home Screen edit mode. `seed`
/// desyncs neighbours so the row doesn't rock in lockstep.
private struct JiggleModifier: ViewModifier {
    let active: Bool
    let seed: Int
    @State private var rotated = false

    func body(content: Content) -> some View {
        let amount: Double = 1.4 + Double(seed % 3) * 0.15
        return content
            .rotationEffect(.degrees(active ? (rotated ? amount : -amount) : 0))
            .animation(active
                       ? .easeInOut(duration: 0.13 + Double(seed % 2) * 0.02).repeatForever(autoreverses: true)
                       : .default,
                       value: rotated)
            .onChange(of: active) { _, on in rotated = on }
            .onAppear { if active { rotated = true } }
    }
}

// MARK: - Done editing card

private struct DoneEditingCard: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 89, height: 89)
            .background(Color(hex: "2F402E"))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag bar scroll tracking

/// Reports the enclosing horizontal `UIScrollView`'s contentOffset.x, contentSize
/// width and bounds width via KVO — reliable where SwiftUI preferences from inside
/// scroll content are not (mirrors `ListScrollDetector` in HomeView). Placed as a
/// background on the scroll content so it can walk up to the scroll view.
/// Shared: the Insights by-month chart reuses it for its own scroll indicator.
struct HorizontalScrollObserver: UIViewRepresentable {
    /// (contentOffset.x, contentSize.width, bounds.width)
    var onScroll: (CGFloat, CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeUIView(context: Context) -> ObserverView {
        let v = ObserverView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.onScroll = onScroll
    }

    final class Coordinator: NSObject {
        var onScroll: (CGFloat, CGFloat, CGFloat) -> Void
        private var offsetObs: NSKeyValueObservation?
        private var sizeObs: NSKeyValueObservation?

        init(onScroll: @escaping (CGFloat, CGFloat, CGFloat) -> Void) { self.onScroll = onScroll }

        func observe(_ sv: UIScrollView) {
            offsetObs?.invalidate(); sizeObs?.invalidate()
            report(sv)
            // Offset drives the thumb position; contentSize catches the initial
            // layout (and tag add/remove) so the bar appears without a scroll.
            offsetObs = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in self?.report(sv) }
            sizeObs = sv.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in self?.report(sv) }
        }

        private func report(_ sv: UIScrollView) {
            let offsetX = sv.contentOffset.x
            let contentW = sv.contentSize.width
            let boundsW = sv.bounds.width
            DispatchQueue.main.async { self.onScroll(offsetX, contentW, boundsW) }
        }

        deinit { offsetObs?.invalidate(); sizeObs?.invalidate() }
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var view: UIView? = self.superview
                while let v = view {
                    if let sv = v as? UIScrollView {
                        self.coordinator?.observe(sv)
                        return
                    }
                    view = v.superview
                }
            }
        }
    }
}

// MARK: - TagFilterCard

private struct TagFilterCard: View {
    let icon: String
    var iconEmoji: String? = nil
    let label: String
    let amountCents: Int
    let currency: String
    let iconBg: Color
    let iconColor: Color
    /// The tag's own colour — tints the card background and the label.
    var tint: Color = Color(hex: "346049")
    let isSelected: Bool
    var isWiggling: Bool = false
    var onLongPress: (() -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
            // Selected: the whole pill fills with Tally green, with the icon square,
            // label and amount flipped to white so they read on the dark fill.
            let effIconBg = isSelected ? Color.white.opacity(0.18) : iconBg
            let effIconColor = isSelected ? Color.white : iconColor
            let effLabelColor = isSelected ? Color.white.opacity(0.75) : tint
            let effAmountColor = isSelected ? Color.white : Color(hex: "1C1C1E")
            return VStack(spacing: 5) {
                // Icon square
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(effIconBg)
                        .frame(width: 36, height: 36)
                    if let iconEmoji {
                        Text(iconEmoji).font(.system(size: 18))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(effIconColor)
                    }
                }

                // Tag name
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(effLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Amount
                Text(CurrencyFormatter.shared.format(cents: amountCents, currencyCode: currency))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(effAmountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(8)
            .frame(width: 89, height: 89)
            // Unselected: a soft tint of the tag's own colour (per Josh's reference).
            // Selected: the Tally-green fill.
            .background(isSelected ? Color(hex: "2F402E") : tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : tint.opacity(0.22),
                        lineWidth: isSelected ? 0 : 0.5
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 7, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            // Subtle iOS-style shake when held to edit.
            .keyframeAnimator(initialValue: 0.0, trigger: isWiggling) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-3, duration: 0.06)
                    CubicKeyframe(3, duration: 0.08)
                    CubicKeyframe(-2.5, duration: 0.08)
                    CubicKeyframe(2.5, duration: 0.08)
                    CubicKeyframe(0, duration: 0.06)
                }
            }
            // Tap and long-press as separate, mutually-exclusive gestures — a
            // Button plus a simultaneous long-press fired both, and the tap's
            // re-render dismissed the just-opened editor on the first try.
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.13) {
                guard let onLongPress else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLongPress()
            }
    }
}

// MARK: - "More" card

private struct MoreTagCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: "pin")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Color(hex: "6E8A70"))
                Text("Pin tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "5E7A62"))
                    .lineLimit(1)
            }
            .frame(width: 89, height: 89)
            .background(Color(hex: "EAF1EA"))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color(hex: "AEC7B1"))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add to Home Bar sheet (unchanged)

struct AddToHomeBarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil }) private var expenses: [ExpenseModel]
    @State private var sortOrder: TagSortOrder = .aToZ
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // Home bar holds standalone tags only. Only scan expenses for recency when the
    // sort actually needs it — otherwise every toggle re-scanned the whole store.
    private var eligibleTags: [TagModel] {
        let recency = sortOrder == .recent ? tagRecency(from: expenses) : [:]
        return allTags.filter { !$0.isGroup }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sortedForDisplay(sortOrder, recency: recency)
    }

    private var hasAnyTag: Bool { allTags.contains { !$0.isGroup } }

    var body: some View {
        // No NavigationStack — its empty inline nav bar pushed the heading far down
        // the sheet. A compact in-content header sits just below the drag handle.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Home bar tags")
                        .font(.dmSerifDisplay(28))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "346049"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)

                Text("Tap a tag to pin or unpin it from your home bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    if !hasAnyTag {
                        VStack(spacing: 12) {
                            Image(systemName: "tag.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(Color(hex: "8F9E94"))
                            Text("No tags yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Text("Create tags first, then pin them here.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        // Search + sort row — mirrors the Home page search/filter row.
                        searchAndSortRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        if eligibleTags.isEmpty {
                            Text("No tags match “\(searchText)”.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(eligibleTags.enumerated()), id: \.element.id) { index, tag in
                                    tagRow(tag)
                                    if index < eligibleTags.count - 1 {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
        // Flush every pin/unpin made in this sheet in a single write on the way out,
        // instead of one write + iCloud export per toggle.
        .onDisappear { try? modelContext.save() }
    }

    // Search field (fills the space) + sort control on the right — the same
    // layout as the Home page search/filter row.
    private var searchAndSortRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "8F9E94"))
                TextField("Search tags…", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "8F9E94"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(searchFocused ? Color(hex: "2F402E") : Color(hex: "DEDAD2"),
                            lineWidth: searchFocused ? 1 : 0.5)
            )

            TagSortMenu(order: $sortOrder)
        }
    }

    private func tagRow(_ tag: TagModel) -> some View {
        HStack(spacing: Spacing.smd) {
            TagIconBadge(tag: tag)
            Text(tag.name)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            HomeToggle(isOn: tag.showOnHome) { toggleHome(tag) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { toggleHome(tag) }
    }

    // Mutate only — the @Query reacts to the in-memory change instantly. Don't
    // save per tap (each save forces a disk write + iCloud export); the flush
    // happens once when the sheet is dismissed (see .onDisappear below).
    private func toggleHome(_ tag: TagModel) {
        tag.showOnHome.toggle()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
