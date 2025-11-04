import SwiftUI

struct TipCardView: View {
    let text: String
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CardView(title: "Tip of the Day") {
                Text(text)
                    .foregroundStyle(SAIFColors.mutedText)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SAIFColors.mutedText)
            }
            .padding(8)
        }
    }
}

