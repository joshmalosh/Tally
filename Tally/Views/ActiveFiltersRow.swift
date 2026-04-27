import SwiftUI
import SwiftData

/// Shown below the search bar only when at least one filter is active.
/// Each chip has an × to remove it individually. Chips fade in/out.
/// When no filters are active this view renders nothing (zero height).
struct ActiveFiltersRow: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]
    @Binding var periodFilter: PeriodFilter

    private var activeTagChips: [TagModel] {
        tags.filter { appState.activeFilterIds.contains($0.id) }
    }

    private var hasPeriodFilter: Bool {
        periodFilter != .allTime
    }

    private var hasAnyFilter: Bool {
        hasPeriodFilter || !appState.activeFilterIds.isEmpty
    }

    var body: some View {
        if hasAnyFilter {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {

                    // Period chip
                    if hasPeriodFilter {
                        filterChip(
                            label: periodFilter.label,
                            color: Color(hex: "2F402E")
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                periodFilter = .allTime
                            }
                        }
                    }

                    // Tag chips
                    ForEach(activeTagChips) { tag in
                        filterChip(
                            label: tag.name,
                            color: tag.tagColor.primaryColor
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.toggleFilter(id: tag.id, isGroup: tag.isGroup)
                            }
                        }
                    }

                    // Clear all — only shown when more than one filter active
                    if activeTagChips.count + (hasPeriodFilter ? 1 : 0) > 1 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.clearFilters()
                                periodFilter = .allTime
                            }
                        } label: {
                            Text("Clear all")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func filterChip(label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "8F9E94"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "DEDAD2"), lineWidth: 0.5))
    }
}
