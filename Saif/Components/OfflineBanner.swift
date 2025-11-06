import SwiftUI

struct OfflineBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.white)
            Text(text).foregroundStyle(.white).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }
}

struct ErrorRetryView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: SAIFSpacing.md) {
            HStack(spacing: SAIFSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).foregroundStyle(SAIFColors.text)
            }
            Button("Retry") { onRetry() }.buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(SAIFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
    }
}

