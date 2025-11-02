import SwiftUI

struct CardView<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
            if let title { Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(SAIFColors.text) }
            if let subtitle { Text(subtitle).font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText) }
            content
        }
        .padding(SAIFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SAIFColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: SAIFRadius.lg)
                .stroke(SAIFColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg, style: .continuous))
        .cardShadow()
    }
}

