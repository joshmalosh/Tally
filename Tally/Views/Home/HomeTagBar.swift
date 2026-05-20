import SwiftUI
import SwiftData
import UIKit

// MARK: - Home Tag Bar

struct HomeTagBar: View {
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @Binding var selectedTagId: String?
    @State private var showingAddSheet = false

    private var homeTags: [TagModel] {
        allTags.filter { $0.showOnHome && !$0.isGroup }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HomeTagPill(label: "All", isSelected: selectedTagId == nil) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTagId = nil
                        }
                    }

                    ForEach(homeTags) { tag in
                        HomeTagPill(label: tag.name, isSelected: selectedTagId == tag.id) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTagId = selectedTagId == tag.id ? nil : tag.id
                            }
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
            }

            // + button pinned at trailing edge
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "8F9E94"))
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(hex: "DEDAD2"), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddToHomeBarSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Pill

private struct HomeTagPill: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.white : Color(hex: "1C1C1E"))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(isSelected ? Color(hex: "346049") : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color(hex: "DEDAD2"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Add to Home Bar sheet

struct AddToHomeBarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagModel.sortOrder) private var allTags: [TagModel]
    @State private var searchText = ""

    private var eligibleTags: [TagModel] {
        allTags
            .filter { !$0.isGroup }
            .filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if eligibleTags.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if allTags.filter({ !$0.isGroup }).isEmpty {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("Tap a tag to toggle it on your home bar.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "8F9E94"))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section {
                            ForEach(eligibleTags) { tag in
                                Button {
                                    tag.showOnHome.toggle()
                                    try? modelContext.save()
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(tag.tagColor.primaryColor)
                                            .frame(width: 10, height: 10)
                                        Text(tag.name)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color(hex: "1C1C1E"))
                                        Spacer()
                                        if tag.showOnHome {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color(hex: "346049"))
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(hex: "F6F5F3").ignoresSafeArea())
                }
            }
            .searchable(text: $searchText, prompt: "Search tags")
            .navigationTitle("Home bar tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "346049"))
                }
            }
        }
    }
}
