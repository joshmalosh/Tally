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
            Capsule()
                .fill(Color(hex: "DEDAD2"))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            Text("Add expense")
                .font(Fonts.headline(20))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, 20)

            VStack(spacing: 10) {
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
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bgPrimary)
    }

    private func entryOption(icon: String, title: String, subtitle: String, mode: AddEntryMode) -> some View {
        Button {
            dismiss()
            onSelect(mode)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: "2F402E"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "E8F0EA"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "C5C5C7"))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: "DEDAD2"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(EntryOptionButtonStyle())
    }
}

private struct EntryOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
