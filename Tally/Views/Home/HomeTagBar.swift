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
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @Query(filter: #Predicate<ExpenseModel> { $0.deletedAt == nil })
    private var activeExpenses: [ExpenseModel]
    @Binding var selectedTagId: String?
    @State private var showingAddSheet = false
    @State private var editingTag: TagModel?
    @State private var wigglingTagId: String?

    private var currency: String { appState.activeCurrency }

    private var homeTags: [TagModel] {
        allTags.filter { $0.showOnHome && !$0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    var body: some View {
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
                    isSelected: selectedTagId == nil
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTagId = nil }
                }

                // Tag cards
                ForEach(homeTags) { tag in
                    let symbol = tag.symbolName ?? tag.icon ?? TagSymbolMap.symbol(for: tag.name)
                    let primary = tag.tagColor.primaryColor
                    let iconBg  = primary

                    TagFilterCard(
                        icon: symbol,
                        iconEmoji: tag.displayEmoji,
                        label: tag.name,
                        amountCents: yearlyTotal(for: tag.id),
                        currency: currency,
                        iconBg: iconBg,
                        iconColor: primary,
                        isSelected: selectedTagId == tag.id,
                        isWiggling: wigglingTagId == tag.id,
                        // iOS "hold to edit" feel: the card shakes + buzzes, then
                        // the editor slides up a beat later so the shake is seen.
                        onLongPress: {
                            wigglingTagId = tag.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                editingTag = tag
                                wigglingTagId = nil
                            }
                        }
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTagId = selectedTagId == tag.id ? nil : tag.id
                        }
                    }
                }

                // "More" card — always last
                MoreTagCard {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAddSheet = true
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
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
    let isSelected: Bool
    var isWiggling: Bool = false
    var onLongPress: (() -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
            VStack(spacing: 5) {
                // Icon square
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 36, height: 36)
                    if let iconEmoji {
                        Text(iconEmoji).font(.system(size: 18))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(iconColor)
                    }
                }

                // Tag name
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "6B7A6A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Amount
                Text(CurrencyFormatter.shared.format(cents: amountCents, currencyCode: currency))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(8)
            .frame(width: 89, height: 89)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            // Selected: a dark Tally green edge so the active tag is obvious.
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(
                        isSelected ? Color(hex: "2F402E") : Color(hex: "DEDAD2").opacity(0.6),
                        lineWidth: isSelected ? 2.5 : 0.5
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
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .foregroundStyle(Color(hex: "DEDAD2"))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Text("Add tag")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "6B7A6A"))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 89, height: 89)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color(hex: "DEDAD2").opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 7, x: 0, y: 2)
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

    private func toggleHome(_ tag: TagModel) {
        tag.showOnHome.toggle()
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
