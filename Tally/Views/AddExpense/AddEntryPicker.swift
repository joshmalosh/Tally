import SwiftUI

enum AddEntryMode: Identifiable {
    case camera
    case photoLibrary
    case uploadFile
    case manual
    case bulkImport

    var id: String {
        switch self {
        case .camera:      "camera"
        case .photoLibrary:"photoLibrary"
        case .uploadFile:  "uploadFile"
        case .manual:      "manual"
        case .bulkImport:  "bulkImport"
        }
    }
}

struct AddEntryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AddEntryMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(hex: "DEDAD2"))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW EXPENSE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "4A5E50"))
                        .tracking(1.2)
                    Text("How'd you\nspend it?")
                        .font(Font.dmSerifDisplay(26))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "EDEAE4"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Camera — hero full-width card
            Button {
                dismiss()
                onSelect(.camera)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "E8F0EA"))
                            .frame(width: 52, height: 52)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color(hex: "2F402E"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text("Snap a receipt")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(hex: "2F402E"))
                                Text("FASTEST")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(hex: "2F402E"))
                                    .tracking(0.4)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: "B8D9C0"))
                            .clipShape(Capsule())
                        }
                        Text("Point, click, parsed in seconds")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "4A5E50").opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "2F402E").opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(EntryOptionButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // 2 × 2 option grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                gridOption(
                    icon: "photo.fill",
                    iconColor: Color(hex: "5B8FC7"),
                    bgColor: Color(hex: "EAF2FB"),
                    title: "From library",
                    subtitle: "Pick photos",
                    mode: .photoLibrary
                )
                gridOption(
                    icon: "doc.fill",
                    iconColor: Color(hex: "D48BC9"),
                    bgColor: Color(hex: "F9EEF8"),
                    title: "Upload file",
                    subtitle: "PDF or doc",
                    mode: .uploadFile
                )
                gridOption(
                    icon: "square.and.pencil",
                    iconColor: Color(hex: "E07070"),
                    bgColor: Color(hex: "FDE8E8"),
                    title: "Quick add",
                    subtitle: "Type it in",
                    mode: .manual
                )
                gridOption(
                    icon: "list.bullet.rectangle",
                    iconColor: Color(hex: "8F9E94"),
                    bgColor: Color(hex: "EDEAE4"),
                    title: "Import from notes",
                    subtitle: "Paste a list",
                    mode: .bulkImport
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Color(hex: "F0EDE6").ignoresSafeArea())
    }

    private func gridOption(
        icon: String,
        iconColor: Color,
        bgColor: Color,
        title: String,
        subtitle: String,
        mode: AddEntryMode
    ) -> some View {
        Button {
            dismiss()
            onSelect(mode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(bgColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "1C1C1E"))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "8F9E94"))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .frame(height: 106)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
