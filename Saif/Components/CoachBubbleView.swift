import SwiftUI

struct CoachBubbleView: View {
    let text: String
    var onTap: () -> Void
    var onClose: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(SAIFColors.primary)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.text)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SAIFColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(SAIFColors.mutedText)
            }
            .offset(x: 8, y: -8)
        }
    }
}

