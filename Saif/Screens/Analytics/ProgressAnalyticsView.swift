import SwiftUI
#if canImport(Charts)
import Charts
#endif

enum AnalyticsTab: String, CaseIterable {
    case overview = "Overview"
    case strength = "Strength"
    case volume = "Volume"
    case body = "Body"
    
    var icon: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .strength: return "dumbbell.fill"
        case .volume: return "chart.line.uptrend.xyaxis"
        case .body: return "figure.stand"
        }
    }
}

struct ProgressAnalyticsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: AnalyticsTab = .overview
    @State private var isLoading = true
    @State private var analyticsData: AnalyticsData?
    
    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SAIFSpacing.md) {
                        ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                            TabButton(title: tab.rawValue, icon: tab.icon, isSelected: selectedTab == tab) {
                                withAnimation { selectedTab = tab }
                            }
                        }
                    }
                    .padding(.horizontal, SAIFSpacing.xl)
                    .padding(.vertical, SAIFSpacing.md)
                }
                .background(SAIFColors.surface)
                
                Divider()
                
                if isLoading {
                    ProgressView("Loading analytics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data = analyticsData {
                    ScrollView {
                        Group {
                            switch selectedTab {
                            case .overview:
                                OverviewTab(data: data)
                            case .strength:
                                StrengthTab(data: data)
                            case .volume:
                                VolumeTab(data: data)
                            case .body:
                                BodyTab()
                            }
                        }
                        .padding(SAIFSpacing.xl)
                    }
                } else {
                    EmptyStateView(
                        icon: "chart.bar",
                        title: "No Data Yet",
                        message: "Complete a few workouts to see your analytics",
                        actionTitle: "Start Workout",
                        action: { /* route from caller */ }
                    )
                }
            }
        }
        .navigationTitle("Progress & Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAnalytics() }
    }
    
    private func loadAnalytics() async {
        guard let userId = authManager.userProfile?.id, let profile = authManager.userProfile else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            analyticsData = try await AnalyticsService.shared.getAnalyticsData(userId: userId, userProfile: profile)
        } catch {
            print("Failed to load analytics: \(error)")
            analyticsData = nil
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? SAIFColors.primary : SAIFColors.mutedText)
            .padding(.horizontal, SAIFSpacing.md)
            .padding(.vertical, SAIFSpacing.sm)
            .background(isSelected ? SAIFColors.primary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: SAIFSpacing.md) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(SAIFColors.mutedText)
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(SAIFColors.text)
            Text(message).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
            if let actionTitle, let action {
                PrimaryButton(actionTitle) { action() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
