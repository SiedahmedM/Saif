import SwiftUI

struct WelcomeView: View {
    @State private var navigateTo: Goal?

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack(spacing: SAIFSpacing.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SAIF")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(SAIFColors.text)
                        .kerning(1.0)
                    Text("Stronger. Smarter. Simpler.")
                        .font(.system(size: 16))
                        .foregroundStyle(SAIFColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CardView(title: "What’s your current goal?") {
                    VStack(spacing: SAIFSpacing.md) {
                        PrimaryButton("Bulk") { navigateTo = .bulk }
                        PrimaryButton("Cut", variant: .accent) { navigateTo = .cut }
                        PrimaryButton("Maintain", variant: .outline) { navigateTo = .maintain }
                    }
                }

                Spacer()
                Text("Designed for gym-goers. No fluff, just progress.")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(SAIFSpacing.xl)
            .navigationDestination(item: $navigateTo) { goal in
                WorkoutCheckinView(goal: goal)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { WelcomeView() }
}
