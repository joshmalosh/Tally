import SwiftUI
import SwiftData

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var periodFilter: PeriodFilter
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Period
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Time period")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "8F9E94"))
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            ForEach([PeriodFilter.allTime, .thisFinancialYear, .thisYear, .thisMonth], id: \.label) { filter in
                                Button {
                                    periodFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.label)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color(hex: "1C1C1E"))
                                        Spacer()
                                        if periodFilter == filter {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color(hex: "2F402E"))
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 13)
                                }
                                .buttonStyle(.plain)
                                if filter != .thisMonth {
                                    Divider().padding(.horizontal, 20)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }

                    // MARK: Tags & Groups
                    let visibleTags = tags
                        .filter { $0.showOnHome && $0.parentId == nil }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                    if !visibleTags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags & groups")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(visibleTags.enumerated()), id: \.element.id) { index, tag in
                                    let isActive = appState.activeFilterIds.contains(tag.id)
                                    Button {
                                        appState.toggleFilter(id: tag.id, isGroup: tag.isGroup)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(tag.tagColor.primaryColor)
                                                .frame(width: 10, height: 10)
                                            Text(tag.name)
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color(hex: "1C1C1E"))
                                            Spacer()
                                            if isActive {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color(hex: "2F402E"))
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 13)
                                    }
                                    .buttonStyle(.plain)
                                    if index < visibleTags.count - 1 {
                                        Divider().padding(.horizontal, 20)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color(hex: "F6F5F3").ignoresSafeArea())
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        appState.clearFilters()
                        periodFilter = .allTime
                    }
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .font(.system(size: 15))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "2F402E"))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
