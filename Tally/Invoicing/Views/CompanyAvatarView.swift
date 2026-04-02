import SwiftUI
import UIKit

struct CompanyAvatarView: View {
    let company: Company
    let size: CGFloat

    private var initials: String {
        company.name
            .components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        Group {
            if let logoData = company.logoData,
               let uiImage = UIImage(data: logoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hex: "2C4A35")
                    Text(initials)
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
