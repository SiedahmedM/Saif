import SwiftUI

struct VolumeTab: View {
    let data: AnalyticsData
    
    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
            CardView(title: "VOLUME TRENDS") {
                Text("Charts and trends coming soon.")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct BodyTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
            CardView(title: "BODY METRICS") {
                Text("Track weight and measurements here (coming soon).")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

