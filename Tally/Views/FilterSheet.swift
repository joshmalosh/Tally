import SwiftUI
import SwiftData

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var periodFilter: PeriodFilter
    @Environment(AppState.self) private var appState
    @Query(sort: \TagModel.sortOrder) private var tags: [TagModel]

    private var standaloneTags: [TagModel] {
        tags
            .filter { !$0.isGroup && $0.parentId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var groups: [TagModel] {
        tags
            .filter { $0.isGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func childTags(of group: TagModel) -> [TagModel] {
        tags
            .filter { $0.parentId == group.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Period
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

                    // All tags & groups
                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags & groups")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(standaloneTags.enumerated()), id: \.element.id) { index, tag in
                                    tagFilterRow(tag: tag)
                                    if index < standaloneTags.count - 1 || !groups.isEmpty {
                                        Divider().padding(.horizontal, 20)
                                    }
                                }

                                ForEach(Array(groups.enumerated()), id: \.element.id) { gIndex, group in
                                    Button {
                                        appState.toggleFilter(id: group.id, isGroup: true)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(group.tagColor.primaryColor)
                                            Text(group.name)
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color(hex: "1C1C1E"))
                                            Spacer()
                                            if appState.activeFilterIds.contains(group.id) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color(hex: "2F402E"))
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 13)
                                    }
                                    .buttonStyle(.plain)

                                    let children = childTags(of: group)
                                    ForEach(children, id: \.id) { child in
                                        Divider().padding(.horizontal, 20)
                                        Button {
                                            appState.toggleFilter(id: child.id, isGroup: false)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Circle()
                                                    .fill(child.tagColor.primaryColor)
                                                    .frame(width: 8, height: 8)
                                                    .padding(.leading, 16)
                                                Text(child.name)
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(Color(hex: "4A5E50"))
                                                Spacer()
                                                if appState.activeFilterIds.contains(child.id) {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(Color(hex: "2F402E"))
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 11)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if gIndex < groups.count - 1 {
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
            .background(Color(hex: "F0EDE6").ignoresSafeArea())
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

    private func tagFilterRow(tag: TagModel) -> some View {
        Button {
            appState.toggleFilter(id: tag.id, isGroup: false)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(tag.tagColor.primaryColor)
                    .frame(width: 10, height: 10)
                Text(tag.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer()
                if appState.activeFilterIds.contains(tag.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "2F402E"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}
