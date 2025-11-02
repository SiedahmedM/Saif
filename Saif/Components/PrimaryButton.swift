import SwiftUI

enum ButtonVariant { case primary, accent, outline }

struct PrimaryButton: View {
    let title: String
    let variant: ButtonVariant
    let action: () -> Void

    init(_ title: String, variant: ButtonVariant = .primary, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, SAIFSpacing.lg)
                .foregroundStyle(textColor)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: SAIFRadius.xl)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: some ShapeStyle {
        switch variant {
        case .primary: return SAIFColors.primary
        case .accent:  return SAIFColors.accent
        case .outline: return Color.clear
        }
    }

    private var textColor: Color {
        switch variant {
        case .outline: return SAIFColors.text
        default: return .white
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outline: return SAIFColors.border
        default: return .clear
        }
    }
}

