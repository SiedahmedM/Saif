import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var lastSession: WorkoutSession?
    @State private var showChat = false
    @State private var tipText: String? = nil
    @State private var showTip = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    header
                    if showTip, let tip = tipText {
                        HStack { Spacer(); TipCardView(text: tip, onClose: { dismissTipForToday() }).frame(maxWidth: 340) }
                    }
                    quickActions
                    profileCard
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = authManager.userProfile?.id {
                lastSession = try? await SupabaseService.shared.getLastCompletedSession(userId: id)
            }
        }
        .task {
            // Touch the knowledge singleton so it loads JSON and log a quick sanity check
            _ = TrainingKnowledgeService.shared
            if let ordering = TrainingKnowledgeService.shared.getOrderingPrinciples() {
                print("Ordering OK:", ordering.optimalSequence.prefix(30), "…")
            }
            let chestCount = TrainingKnowledgeService.shared.getExercises(for: "chest").count
            print("Chest research count:", chestCount)
        }
        .task {
            if shouldShowTip() {
                tipText = makeDailyTip()
                showTip = tipText != nil
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                Button { showChat = true } label: {
                    Image(systemName: "message.fill")
                        .foregroundStyle(.white)
                        .padding()
                        .background(SAIFColors.primary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showChat) { ChatBotSheet().presentationDetents([.medium, .large]) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome back,").foregroundStyle(SAIFColors.mutedText)
            Text(authManager.userProfile?.fullName ?? "Athlete").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
        }
    }

    private var quickActions: some View {
        VStack(spacing: SAIFSpacing.md) {
            NavigationLink(destination: WorkoutStartView(selectedPreset: nil)) {
                Text("Start Workout").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg).foregroundStyle(.white).background(SAIFColors.primary).clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
            }
        }
    }

    private var profileCard: some View {
        CardView(title: "Your Profile") {
            VStack(alignment: .leading, spacing: 6) {
                if let p = authManager.userProfile {
                    Text("Goal: \(p.primaryGoal.displayName)")
                    Text("Experience: \(p.fitnessLevel.displayName)")
                    Text("Frequency: \(p.workoutFrequency)x/week")
                    Text("Gym: \(p.gymType.displayName)")
                    if let s = lastSession {
                        Text("Last: \(s.workoutType.capitalized) on \(s.startedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                } else {
                    Text("Complete onboarding to personalize your plan.").foregroundStyle(SAIFColors.mutedText)
                }
            }
        }
    }
}

private let tipDismissKey = "coachDailyTipDismissedAt"

extension HomeDashboardView {
    private func shouldShowTip() -> Bool {
        if let ts = UserDefaults.standard.object(forKey: tipDismissKey) as? Date {
            let cal = Calendar.current
            return !cal.isDateInToday(ts)
        }
        return true
    }
    private func dismissTipForToday() {
        UserDefaults.standard.set(Date(), forKey: tipDismissKey)
        withAnimation { showTip = false }
    }
}

extension HomeDashboardView {
    func makeDailyTip() -> String? {
        guard let profile = authManager.userProfile else { return nil }
        let goal = profile.primaryGoal
        let level = profile.fitnessLevel
        let freq = profile.workoutFrequency
        let last = lastSession
        var lines: [String] = []
        if let last {
            let days = Calendar.current.dateComponents([.day], from: last.startedAt, to: Date()).day ?? 0
            if days >= 2 { lines.append("It's been \(days) days since your last session — let's build momentum today.") }
            else if days == 0 { lines.append("Nice consistency — keep the streak going today.") }
        }
        switch (level, goal) {
        case (.beginner, .bulk): lines.append("Start with key compounds and aim for 6–12 reps.")
        case (.beginner, .maintain): lines.append("Keep intensity moderate and focus on clean technique (8–10 reps).")
        case (.intermediate, .bulk): lines.append("Add a small progression (load or reps) on a primary lift.")
        case (.intermediate, .cut): lines.append("Preserve strength with steady tempo and moderate volume.")
        case (.advanced, .bulk): lines.append("Rotate intensities (heavy/moderate) to manage fatigue.")
        default: lines.append("Prioritize quality compounds, then accessories for weak links.")
        }
        if freq >= 5 && lines.count < 2 { lines.append("Shorter sessions still count — keep recovery in check.") }
        let tip = lines.prefix(2).joined(separator: " ")
        return tip.isEmpty ? nil : tip
    }
}

struct ChatBotSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var messages: [String] = ["Hi, I’m your SAIF coach. How can I help?"]
    @State private var input: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.indices, id: \.self) { i in
                            Text(messages[i]).padding(10).background(i % 2 == 0 ? SAIFColors.surface : SAIFColors.primary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
                HStack {
                    TextField("Ask me anything...", text: $input).textFieldStyle(.roundedBorder)
                    Button("Send") { send() }
                }.padding()
            }
            .navigationTitle("Coach")
        }
    }

    private func send() {
        guard !input.isEmpty else { return }
        let prompt = input
        messages.append(prompt)
        input = ""
        Task {
            let profile = authManager.userProfile
            let context = "User: \(profile?.fullName ?? "Athlete"); Goal: \(profile?.primaryGoal.rawValue ?? ""); Experience: \(profile?.fitnessLevel.rawValue ?? ""); Frequency: \(profile?.workoutFrequency ?? 0)"
            let reply = try? await OpenAIService.shared.getChatReply(system: "You are a helpful fitness coach.", user: context + "\nQuestion: " + prompt)
            messages.append(reply ?? "I’ll think about that and get back to you.")
        }
    }
}
