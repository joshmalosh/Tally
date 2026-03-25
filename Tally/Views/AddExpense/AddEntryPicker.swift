import SwiftUI

enum AddEntryMode: Identifiable {
    case camera
    case photoLibrary
    case uploadFile
    case manual
    case bulkImport

    var id: String {
        switch self {
        case .camera: "camera"
        case .photoLibrary: "photoLibrary"
        case .uploadFile: "uploadFile"
        case .manual: "manual"
        case .bulkImport: "bulkImport"
        }
    }
}

struct AddEntryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AddEntryMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            handle

            Text("Add expense")
                .font(Fonts.headline(18))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                entryOption(
                    icon: "camera.fill",
                    title: "Snap receipt",
                    subtitle: "Take a photo of your receipt",
                    mode: .camera
                )
                entryOption(
                    icon: "photo.fill",
                    title: "Upload image",
                    subtitle: "Choose a photo from your library",
                    mode: .photoLibrary
                )
                entryOption(
                    icon: "doc.fill",
                    title: "Upload file",
                    subtitle: "Import a PDF or document",
                    mode: .uploadFile
                )
                entryOption(
                    icon: "square.and.pencil",
                    title: "Quick add",
                    subtitle: "Log an expense manually",
                    mode: .manual
                )
                entryOption(
                    icon: "list.bullet.rectangle",
                    title: "Import from notes",
                    subtitle: "Turn a list or photo into tagged expenses",
                    mode: .bulkImport
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.borderColor)
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.sm)
    }

    private func entryOption(icon: String, title: String, subtitle: String, mode: AddEntryMode) -> some View {
        Button {
            dismiss()
            onSelect(mode)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.brandTint)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Fonts.body(16))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(Fonts.caption(13))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(Spacing.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}
