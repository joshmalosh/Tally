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
            HStack {
                Spacer()
                Capsule()
                    .fill(Color(hex: "DEDAD2"))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 20)

            Text("Add expense")
                .font(Fonts.headline(18))
                .foregroundStyle(Color.textPrimary)
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
                    subtitle: "Turn a list into tagged expenses",
                    mode: .bulkImport
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .padding(.top, 20)
        .background(Color.bgPrimary)
    }

    private func entryOption(icon: String, title: String, subtitle: String, mode: AddEntryMode) -> some View {
        Button {
            dismiss()
            onSelect(mode)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "2F402E"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "E8F0EA"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }
}
