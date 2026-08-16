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

    private var currency: String { appState.defaultCurrency }

    private var homeTags: [TagModel] {
        allTags.filter { $0.showOnHome && !$0.isGroup }
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
                    let iconBg  = primary.opacity(0.15)

                    TagFilterCard(
                        icon: symbol,
                        label: tag.name,
                        amountCents: yearlyTotal(for: tag.id),
                        currency: currency,
                        iconBg: iconBg,
                        iconColor: primary,
                        isSelected: selectedTagId == tag.id,
                        onLongPress: { editingTag = tag }
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
    let label: String
    let amountCents: Int
    let currency: String
    let iconBg: Color
    let iconColor: Color
    let isSelected: Bool
    var onLongPress: (() -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
            VStack(spacing: 4) {
                // Icon square
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                // Tag name
                Text(label)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color(hex: "6B7A6A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Amount
                Text(CurrencyFormatter.shared.format(cents: amountCents, currencyCode: currency))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(6)
            .frame(width: 74, height: 74)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color(hex: "B8D4C0") : Color(hex: "DEDAD2").opacity(0.6),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            // Tap and long-press as separate, mutually-exclusive gestures — a
            // Button plus a simultaneous long-press fired both, and the tap's
            // re-render dismissed the just-opened editor on the first try.
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.4) {
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
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .foregroundStyle(Color(hex: "DEDAD2"))
                        .frame(width: 30, height: 30)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Text("More")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color(hex: "6B7A6A"))
            }
            .padding(6)
            .frame(width: 74, height: 74)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: "DEDAD2").opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
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

    // Home bar holds standalone tags only.
    private var eligibleTags: [TagModel] {
        allTags.filter { !$0.isGroup }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sortedForDisplay(sortOrder, recency: tagRecency(from: expenses))
    }

    private var hasAnyTag: Bool { allTags.contains { !$0.isGroup } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Home bar tags")
                        .font(.dmSerifDisplay(28))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
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
                                        Divider().padding(.leading, 44)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "346049"))
                }
            }
        }
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
        HStack(spacing: 12) {
            Circle()
                .fill(tag.tagColor.primaryColor)
                .frame(width: 12, height: 12)
            Text(tag.name)
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Spacer()
            HomeToggle(isOn: tag.showOnHome) { toggleHome(tag) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { toggleHome(tag) }
    }

    private func toggleHome(_ tag: TagModel) {
        tag.showOnHome.toggle()
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
