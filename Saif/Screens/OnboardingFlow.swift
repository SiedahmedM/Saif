import SwiftUI

struct OnboardingCoordinator: View {
    // Optional reference for when called from AuthFlow
    var authManager: AuthManager? = nil
    @AppStorage("onboarding_current_step") private var savedStep: Int = 0
    @AppStorage("onboarding_incomplete") private var onboardingIncomplete: Bool = true
    @AppStorage("onboarding_name") private var savedName: String = ""
    @AppStorage("onboarding_goal") private var savedGoal: String = Goal.bulk.rawValue
    @AppStorage("onboarding_fitness") private var savedFitness: String = FitnessLevel.beginner.rawValue
    @AppStorage("onboarding_freq") private var savedFreq: Int = 3
    @AppStorage("onboarding_gym") private var savedGym: String = GymType.commercial.rawValue
    @AppStorage("onboarding_injuries") private var savedInjuries: String = ""
    @State private var currentStep = 0
    @State private var profile = OnboardingProfile()

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()

            TabView(selection: $currentStep) {
                OnboardingWelcome(onNext: { currentStep += 1 })
                    .tag(0)

                OnboardingName(profile: $profile, onNext: { currentStep += 1 })
                    .tag(1)

                OnboardingGoal(profile: $profile, onNext: { currentStep += 1 })
                    .tag(2)

                OnboardingExperience(profile: $profile, onNext: { currentStep += 1 })
                    .tag(3)

                OnboardingFrequency(profile: $profile, onNext: { currentStep += 1 })
                    .tag(4)

                OnboardingEquipment(profile: $profile, onNext: { currentStep += 1 })
                    .tag(5)

                OnboardingLimitations(profile: $profile, onNext: { currentStep += 1 })
                    .tag(6)

                OnboardingComplete(profile: profile, authManager: authManager)
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onboardingIncomplete = true; savedStep = currentStep }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep > 0 { Button("Back") { currentStep = max(0, currentStep-1) } }
                }
            }

            VStack {
                HStack(spacing: 8) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentStep ? SAIFColors.primary : SAIFColors.idle)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, SAIFSpacing.xl)
                .padding(.top, SAIFSpacing.lg)
                Spacer()
            }
        }
        .onAppear {
            if onboardingIncomplete {
                currentStep = savedStep
                profile = OnboardingProfile(
                    name: savedName,
                    goal: Goal(rawValue: savedGoal) ?? .bulk,
                    fitnessLevel: FitnessLevel(rawValue: savedFitness) ?? .beginner,
                    workoutFrequency: savedFreq,
                    gymType: GymType(rawValue: savedGym) ?? .commercial,
                    injuries: savedInjuries
                )
            }
        }
        .onChange(of: currentStep) { _, new in savedStep = new }
        .onChange(of: profile.name) { _, new in savedName = new }
        .onChange(of: profile.goal) { _, new in savedGoal = new.rawValue }
        .onChange(of: profile.fitnessLevel) { _, new in savedFitness = new.rawValue }
        .onChange(of: profile.workoutFrequency) { _, new in savedFreq = new }
        .onChange(of: profile.gymType) { _, new in savedGym = new.rawValue }
        .onChange(of: profile.injuries) { _, new in savedInjuries = new }
    }
}

// Temporary state holder while onboarding
struct OnboardingProfile {
    var name: String = ""
    var goal: Goal = .bulk
    var fitnessLevel: FitnessLevel = .beginner
    var workoutFrequency: Int = 3
    var gymType: GymType = .commercial
    var injuries: String = ""
}

// Step 1: Welcome
struct OnboardingWelcome: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: SAIFSpacing.xl) {
            Spacer()
            VStack(alignment: .center, spacing: SAIFSpacing.md) {
                Text("👋").font(.system(size: 80))
                Text("Welcome to SAIF")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(SAIFColors.text)
                Text("Your AI-powered training partner that adapts to your goals, tracks every rep, and optimizes your workouts in real-time.")
                    .font(.system(size: 16))
                    .foregroundStyle(SAIFColors.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SAIFSpacing.lg)
            }
            Spacer()
            VStack(spacing: SAIFSpacing.md) {
                PrimaryButton("Get Started") { onNext() }
                Button("Skip for now") { onNext() }
                    .foregroundStyle(SAIFColors.mutedText)
            }
            .padding(SAIFSpacing.xl)
        }
    }
}

// Step 2: Goal Selection
struct OnboardingName: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "What's your name?",
            subtitle: "We'll personalize your experience."
        ) {
            VStack(spacing: SAIFSpacing.lg) {
                TextField("Your name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 4)
                PrimaryButton("Continue") { onNext() }.disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct OnboardingGoal: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "What's your primary goal?",
            subtitle: "We'll tailor your workout recommendations based on this."
        ) {
            VStack(spacing: SAIFSpacing.md) {
                GoalCard(goal: .bulk, icon: "💪", description: "Build muscle mass and strength", isSelected: profile.goal == .bulk) { profile.goal = .bulk }
                GoalCard(goal: .cut, icon: "🔥", description: "Lose fat while maintaining muscle", isSelected: profile.goal == .cut) { profile.goal = .cut }
                GoalCard(goal: .maintain, icon: "⚖️", description: "Maintain current physique and strength", isSelected: profile.goal == .maintain) { profile.goal = .maintain }
            }
            PrimaryButton("Continue") { onNext() }
                .padding(.top, SAIFSpacing.lg)
        }
    }
}

// Step 3: Experience Level
struct OnboardingExperience: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "What's your experience level?",
            subtitle: "This helps us recommend appropriate exercises and volume."
        ) {
            VStack(spacing: SAIFSpacing.md) {
                ExperienceCard(level: .beginner, description: "New to lifting or less than 1 year", isSelected: profile.fitnessLevel == .beginner) { profile.fitnessLevel = .beginner }
                ExperienceCard(level: .intermediate, description: "1-3 years of consistent training", isSelected: profile.fitnessLevel == .intermediate) { profile.fitnessLevel = .intermediate }
                ExperienceCard(level: .advanced, description: "3+ years, strong foundation", isSelected: profile.fitnessLevel == .advanced) { profile.fitnessLevel = .advanced }
            }
            PrimaryButton("Continue") { onNext() }
                .padding(.top, SAIFSpacing.lg)
        }
    }
}

// Step 4: Workout Frequency
struct OnboardingFrequency: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "How often can you train?",
            subtitle: "Be realistic—consistency beats intensity."
        ) {
            VStack(spacing: SAIFSpacing.xl) {
                VStack(spacing: SAIFSpacing.sm) {
                    Text("\(profile.workoutFrequency)")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(SAIFColors.primary)
                    Text("days per week")
                        .font(.system(size: 16))
                        .foregroundStyle(SAIFColors.mutedText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SAIFSpacing.xl)
                .background(SAIFColors.surface)
                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.xl).stroke(SAIFColors.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
                .cardShadow()

                Picker("Frequency", selection: $profile.workoutFrequency) {
                    ForEach(2...7, id: \.self) { days in
                        Text("\(days)").tag(days)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }
            PrimaryButton("Continue") { onNext() }
                .padding(.top, SAIFSpacing.lg)
        }
    }
}

// Step 5: Equipment Access
struct OnboardingEquipment: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "What equipment do you have access to?",
            subtitle: "We'll recommend exercises based on your setup."
        ) {
            VStack(spacing: SAIFSpacing.md) {
                EquipmentCard(type: .commercial, icon: "🏋️", description: "Full gym with machines, free weights, cables", isSelected: profile.gymType == .commercial) { profile.gymType = .commercial }
                EquipmentCard(type: .home, icon: "🏠", description: "Home gym with dumbbells, barbell, bench", isSelected: profile.gymType == .home) { profile.gymType = .home }
                EquipmentCard(type: .minimal, icon: "🎯", description: "Minimal equipment (bodyweight, bands, dumbbells)", isSelected: profile.gymType == .minimal) { profile.gymType = .minimal }
            }
            PrimaryButton("Continue") { onNext() }
                .padding(.top, SAIFSpacing.lg)
        }
    }
}

// Step 6: Injuries/Limitations
struct OnboardingLimitations: View {
    @Binding var profile: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        OnboardingTemplate(
            title: "Any injuries or limitations?",
            subtitle: "Optional—helps us avoid aggravating existing issues."
        ) {
            VStack(spacing: SAIFSpacing.lg) {
                TextEditor(text: $profile.injuries)
                    .frame(height: 150)
                    .padding(SAIFSpacing.md)
                    .background(SAIFColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(SAIFColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                    .foregroundStyle(SAIFColors.text)
                Text("e.g., 'Lower back pain,' 'Shoulder impingement,' 'Knee issues'")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: SAIFSpacing.md) {
                PrimaryButton("Continue") { onNext() }
                Button("Skip") { onNext() }
                    .foregroundStyle(SAIFColors.mutedText)
            }
            .padding(.top, SAIFSpacing.lg)
        }
    }
}

// Step 7: Complete
struct OnboardingComplete: View {
    let profile: OnboardingProfile
    var authManager: AuthManager? = nil
    @State private var isLoading = false
    @State private var goFirst = false

    var body: some View {
        OnboardingTemplate(
            title: "You're all set!",
            subtitle: "Ready to start your first workout?"
        ) {
            VStack(spacing: SAIFSpacing.lg) {
                SummaryRow(label: "Goal", value: profile.goal.displayName)
                SummaryRow(label: "Experience", value: profile.fitnessLevel.displayName)
                SummaryRow(label: "Frequency", value: "\(profile.workoutFrequency)x/week")
                SummaryRow(label: "Equipment", value: profile.gymType.displayName)
            }
            .padding(SAIFSpacing.lg)
            .background(SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.xl).stroke(SAIFColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
            .cardShadow()

            if isLoading {
                ProgressView().padding(.top, SAIFSpacing.xl)
            } else {
                PrimaryButton("Start Training") {
                    isLoading = true
                    Task {
                        if let ok = await authManager?.completeOnboarding(profile: profile), ok {
                            UserDefaults.standard.set(false, forKey: "onboarding_incomplete")
                            goFirst = true
                        }
                        isLoading = false
                    }
                }
                .padding(.top, SAIFSpacing.xl)
            }
            NavigationLink(isActive: $goFirst) { FirstWorkoutIntroView() } label: { EmptyView() }
        }
    }
}

// Template + Cards + Row
struct OnboardingTemplate<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                    Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                    Text(subtitle).font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
                }
                content
            }
            .padding(SAIFSpacing.xl)
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    let icon: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SAIFSpacing.md) {
                Text(icon).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.rawValue).font(.system(size: 18, weight: .semibold)).foregroundStyle(SAIFColors.text)
                    Text(description).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(SAIFColors.primary).font(.system(size: 24)) }
            }
            .padding(SAIFSpacing.lg)
            .background(isSelected ? SAIFColors.primary.opacity(0.1) : SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(isSelected ? SAIFColors.primary : SAIFColors.border, lineWidth: isSelected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

struct ExperienceCard: View {
    let level: FitnessLevel
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName).font(.system(size: 18, weight: .semibold)).foregroundStyle(SAIFColors.text)
                    Text(description).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(SAIFColors.primary).font(.system(size: 24)) }
            }
            .padding(SAIFSpacing.lg)
            .background(isSelected ? SAIFColors.primary.opacity(0.1) : SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(isSelected ? SAIFColors.primary : SAIFColors.border, lineWidth: isSelected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

struct EquipmentCard: View {
    let type: GymType
    let icon: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SAIFSpacing.md) {
                Text(icon).font(.system(size: 36))
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName).font(.system(size: 18, weight: .semibold)).foregroundStyle(SAIFColors.text)
                    Text(description).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(SAIFColors.primary).font(.system(size: 24)) }
            }
            .padding(SAIFSpacing.lg)
            .background(isSelected ? SAIFColors.primary.opacity(0.1) : SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(isSelected ? SAIFColors.primary : SAIFColors.border, lineWidth: isSelected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
            Spacer()
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(SAIFColors.text)
        }
    }
}

#Preview {
    OnboardingCoordinator()
}
