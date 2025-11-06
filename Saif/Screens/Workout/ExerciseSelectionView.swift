import SwiftUI

struct ExerciseSelectionView: View {
    let muscleGroup: String
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var authManager: AuthManager
    @State private var goLog = false
    @State private var selectedExercise: Exercise?
    @State private var goSummary = false
    @State private var goNextGroups = false
    @State private var showInfo = false
    @State private var infoDetail: ExerciseDetail? = nil
    @State private var infoIsCompound: Bool = true
    @State private var userInjuries: [String] = []
    @State private var showPlan = false
    @State private var showToast = false
    @State private var toastMessage: String = ""
    @State private var showPrefSheet = false
    @State private var prefExerciseId: UUID? = nil
    @State private var prefExerciseName: String = ""

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    Text(muscleGroup.capitalized).font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                    Text("Pick one to begin sets").foregroundStyle(SAIFColors.mutedText)

                    // Volume Progress Card
                    SelectionVolumeProgressCard(
                        muscleGroup: muscleGroup,
                        setsCompleted: workoutManager.getSetsCompletedForGroup(muscleGroup),
                        targetRange: workoutManager.getVolumeTarget(for: muscleGroup)
                    )

                    if let dbg = workoutManager.exerciseDebug {
                        CardView(title: "Debug: Supabase Query") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("workout_type: \(dbg.requestedWorkoutType)")
                                Text("muscle_group: \(dbg.requestedGroup)")
                                Text("matched: \(dbg.matchedCount)")
                                Text("all for type: \(dbg.allForTypeCount)")
                                if let e = workoutManager.error { Text(e).foregroundStyle(.red) }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(SAIFColors.mutedText)
                        }
                    }

                    if workoutManager.isLoading && workoutManager.availableExercises.isEmpty && workoutManager.exerciseRecommendations.isEmpty {
                        CardView { HStack { ProgressView(); Text("Loading exercises...").foregroundStyle(SAIFColors.mutedText) } }
                    }
                    if !workoutManager.isLoading && workoutManager.availableExercises.isEmpty {
                        CardView(title: "No exercises found") {
                            VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                Text("We couldn't find exercises for \(muscleGroup.capitalized) in this workout type.")
                                    .foregroundStyle(SAIFColors.mutedText)
                                Text("Ensure 'exercises' has rows with workout_type='\(workoutManager.currentSession?.workoutType ?? "")' and muscle_group like '\(muscleGroup)'.")
                                    .foregroundStyle(SAIFColors.mutedText)
                                Button("Retry") { Task { await workoutManager.getExerciseRecommendations(for: muscleGroup) } }
                                    .foregroundStyle(SAIFColors.primary)
                            }
                        }
                    }
                    // Show AI-ordered list when available
                    LazyVStack(spacing: SAIFSpacing.md) {
                    ForEach(workoutManager.exerciseRecommendations) { rec in
                        let ex = workoutManager.availableExercises.first { $0.name == rec.exerciseName }
                        let exId = ex?.id
                        let isDone = exId.map { workoutManager.completedExerciseIds.contains($0) } ?? false
                        let detail = TrainingKnowledgeService.shared.findExercise(named: rec.exerciseName)
                        let safetyStatus: ExerciseSafetyStatus = {
                            guard let detail else { return .safe }
                            let res = InjuryRuleEngine.shared.filterExercises([detail], injuries: userInjuries).first
                            return res?.status ?? .safe
                        }()

                        AICandidateRow(
                            title: rec.exerciseName,
                            sets: rec.sets,
                            priority: rec.priority,
                            isDone: isDone,
                            safetyStatus: safetyStatus,
                            isFavorite: exId.map { workoutManager.isFavorite($0) } ?? false,
                            onInfo: {
                                infoIsCompound = ex?.isCompound ?? true
                                infoDetail = workoutManager.researchDetails(for: rec.exerciseName)
                                showInfo = true
                            },
                            onToggleFavorite: {
                                guard let id = exId else { return }
                                Task {
                                    let fav = workoutManager.isFavorite(id)
                                    await workoutManager.setExercisePreference(exerciseId: id, level: fav ? .neutral : .favorite, reason: nil)
                                    withAnimation { showToast = true; toastMessage = fav ? "Removed from favorites" : "Added to favorites" }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { showToast = false } }
                                }
                            },
                            onLongPressFavorite: {
                                if let id = exId {
                                    prefExerciseId = id
                                    prefExerciseName = rec.exerciseName
                                    showPrefSheet = true
                                }
                            },
                            onReplace: {
                                let chosen = ex ?? Exercise(id: UUID(), name: rec.exerciseName, muscleGroup: muscleGroup, workoutType: workoutManager.currentSession?.workoutType ?? "", equipment: [], difficulty: .beginner, isCompound: true, description: "", formCues: [])
                                Task {
                                    await workoutManager.replaceNextPlannedExercise(group: muscleGroup, with: chosen)
                                    toastMessage = "Plan updated: replaced next \(muscleGroup.capitalized) exercise"
                                    showToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showToast = false }
                                }
                            },
                            onTap: {
                                let chosen = ex ?? Exercise(id: UUID(), name: rec.exerciseName, muscleGroup: muscleGroup, workoutType: workoutManager.currentSession?.workoutType ?? "", equipment: [], difficulty: .beginner, isCompound: true, description: "", formCues: [])
                                selectedExercise = chosen
                                Task {
                                    await workoutManager.replaceNextPlannedExercise(group: muscleGroup, with: chosen)
                                    await workoutManager.selectExercise(chosen)
                                    await MainActor.run { goLog = true }
                                }
                            },
                            disabled: exId.map { workoutManager.completedExerciseIds.contains($0) } ?? false
                        )
                    }
                    }

                    // Fallback: if AI list is empty but we have exercises, show them directly
                    if workoutManager.exerciseRecommendations.isEmpty && !workoutManager.availableExercises.isEmpty {
                        LazyVStack(spacing: SAIFSpacing.md) {
                        ForEach(workoutManager.availableExercises, id: \.id) { ex in
                            let isDone = workoutManager.completedExerciseIds.contains(ex.id)
                            AvailableExerciseRow(
                                title: ex.name,
                                subtitle: ex.muscleGroup.capitalized,
                                isDone: isDone,
                                isFavorite: workoutManager.isFavorite(ex.id),
                                onToggleFavorite: {
                                    Task {
                                        let fav = workoutManager.isFavorite(ex.id)
                                        await workoutManager.setExercisePreference(exerciseId: ex.id, level: fav ? .neutral : .favorite, reason: nil)
                                        withAnimation { showToast = true; toastMessage = fav ? "Removed from favorites" : "Added to favorites" }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { showToast = false } }
                                    }
                                },
                                onLongPressFavorite: {
                                    prefExerciseId = ex.id
                                    prefExerciseName = ex.name
                                    showPrefSheet = true
                                },
                                onTap: {
                                    selectedExercise = ex
                                    Task {
                                        await workoutManager.selectExercise(ex)
                                        await MainActor.run { goLog = true }
                                    }
                                }
                            )
                            .disabled(isDone)
                        }
                        }
                    }

                    if !workoutManager.availableExercises.isEmpty {
                        PrimaryButton("Choose Another Muscle Group", variant: .outline) { goNextGroups = true }
                    }

                    NavigationLink(isActive: $goLog) {
                        if let ex = selectedExercise { ExerciseLoggingView(exercise: ex).environmentObject(workoutManager) } else { EmptyView() }
                    } label: { EmptyView() }
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("End") { goSummary = true } }
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Plan") { showPlan = true } } }
        .sheet(isPresented: $showPlan) {
            if let plan = workoutManager.currentPlan {
                NavigationStack { SessionPlanView(plan: plan).environmentObject(workoutManager) }
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showInfo) {
            ResearchInfoView(exercise: infoDetail, isCompound: infoIsCompound)
        }
        .sheet(isPresented: $showPrefSheet) {
            ExercisePreferenceSheet(
                exerciseId: prefExerciseId,
                exerciseName: prefExerciseName,
                muscleGroup: muscleGroup
            )
            .environmentObject(workoutManager)
        }
        .background(
            Group {
                NavigationLink(isActive: $goSummary) { PostWorkoutSummaryView() } label: { EmptyView() }
                // Retired legacy next suggestions view
                EmptyView()
            }
        )
        .task {
            // Parse injuries from profile array into tags
            let injuriesText = (authManager.userProfile?.injuriesLimitations ?? []).joined(separator: ", ")
            userInjuries = InjuryRuleEngine.shared.parseInjuries(from: injuriesText)
            if workoutManager.availableExercises.isEmpty || workoutManager.exerciseDebug == nil {
                await workoutManager.getExerciseRecommendations(for: muscleGroup)
            }
        }
    }
}

// MARK: - Row Components
private struct AICandidateRow: View {
    let title: String
    let sets: Int?
    let priority: Int
    let isDone: Bool
    let safetyStatus: ExerciseSafetyStatus
    let isFavorite: Bool
    let onInfo: () -> Void
    let onToggleFavorite: () -> Void
    let onLongPressFavorite: () -> Void
    let onReplace: () -> Void
    let onTap: () -> Void
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundStyle(isDone ? SAIFColors.mutedText : SAIFColors.text)
                        .font(.system(size: 18, weight: .semibold))
                    HStack(spacing: 8) {
                        Text("Priority \(priority)").foregroundStyle(SAIFColors.mutedText).font(.system(size: 14))
                        if let sets { Text("Sets: \(sets)").foregroundStyle(SAIFColors.mutedText).font(.system(size: 14)) }
                        if isDone { Text("Completed").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.primary) }
                    }
                }
                Spacer()
                SafetyStatusBadge(status: safetyStatus)
                HStack(spacing: 12) {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle").foregroundStyle(SAIFColors.primary)
                    }
                    Button(action: {
                        print("❤️ Heart tapped for exercise: \(title)")
                        print("  - Current favorite status: \(isFavorite)")
                        onToggleFavorite()
                    }) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart").foregroundStyle(isFavorite ? .red : SAIFColors.mutedText)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPressFavorite() })
                    Button(action: onReplace) {
                        Text("Replace").font(.system(size: 12, weight: .semibold))
                    }
                    Image(systemName: "chevron.right").foregroundStyle(SAIFColors.mutedText)
                }
            }
        }
        .padding(SAIFSpacing.lg)
        .background(SAIFColors.surface)
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .disabled(disabled)
    }
}

private struct AvailableExerciseRow: View {
    let title: String
    let subtitle: String
    let isDone: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onLongPressFavorite: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(isDone ? SAIFColors.mutedText : SAIFColors.text).font(.system(size: 18, weight: .semibold))
                HStack(spacing: 8) {
                    Text(subtitle).foregroundStyle(SAIFColors.mutedText).font(.system(size: 14))
                    if isDone { Text("Completed").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.primary) }
                }
            }
            Spacer()
            Button(action: {
                print("❤️ Heart tapped for exercise: \(title)")
                print("  - Current favorite status: \(isFavorite)")
                onToggleFavorite()
            }) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : SAIFColors.mutedText)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture().onEnded { _ in onLongPressFavorite() })
            Image(systemName: "chevron.right").foregroundStyle(SAIFColors.mutedText)
        }
        .padding(SAIFSpacing.lg)
        .background(SAIFColors.surface)
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview { NavigationStack { ExerciseSelectionView(muscleGroup: "chest").environmentObject(WorkoutManager()).environmentObject(AuthManager()) } }

struct SafetyStatusBadge: View {
    let status: ExerciseSafetyStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var icon: String {
        switch status { case .safe: return "checkmark.shield.fill"; case .caution: return "exclamationmark.triangle.fill"; case .avoid: return "xmark.shield.fill" }
    }
    private var label: String {
        switch status { case .safe: return "Safe"; case .caution: return "Caution"; case .avoid: return "Avoid" }
    }
    private var color: Color {
        switch status { case .safe: return .green; case .caution: return .orange; case .avoid: return .red }
    }
}

// MARK: - Volume Progress Card (ExerciseSelection)
private struct SelectionVolumeProgressCard: View {
    let muscleGroup: String
    let setsCompleted: Int
    let targetRange: (min: Int, max: Int, status: String)?

    var body: some View {
        CardView(title: "📊 \(muscleGroup.capitalized) Volume Progress") {
            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                if let target = targetRange {
                    // Progress text
                    HStack {
                        Text("Today:")
                            .font(.system(size: 16, weight: .medium))
                        Text("\(setsCompleted) / \(target.min)-\(target.max) sets")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SAIFColors.primary)
                        Spacer()
                        Text("\(progressPercentage(target))%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SAIFColors.border)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressColor(target))
                                .frame(width: geometry.size.width * CGFloat(progressPercentage(target)) / 100, height: 12)
                        }
                    }
                    .frame(height: 12)
                    // Status message
                    HStack(spacing: 6) {
                        Text(statusIcon(target))
                            .font(.system(size: 14))
                        Text(statusMessage(target))
                            .font(.system(size: 14))
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                    .padding(.top, 4)
                    // Weekly context
                    Text(target.status)
                        .font(.system(size: 12))
                        .foregroundStyle(SAIFColors.mutedText)
                        .padding(.top, 2)
                } else {
                    // Fallback if no research data
                    HStack {
                        Text("Today:")
                            .font(.system(size: 16, weight: .medium))
                        Text("\(setsCompleted) sets completed")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SAIFColors.primary)
                    }
                    Text("Keep going! Aim for 10-20 sets per muscle group per week.")
                        .font(.system(size: 14))
                        .foregroundStyle(SAIFColors.mutedText)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func progressPercentage(_ target: (min: Int, max: Int, status: String)) -> Int {
        let targetMidpoint = max((target.min + target.max) / 2, 1)
        let percentage = min(Int(Double(setsCompleted) / Double(targetMidpoint) * 100), 100)
        return max(percentage, 0)
    }

    private func progressColor(_ target: (min: Int, max: Int, status: String)) -> Color {
        if setsCompleted < target.min {
            return SAIFColors.accent.opacity(0.6)
        } else if setsCompleted <= target.max {
            return SAIFColors.primary
        } else {
            return Color.orange
        }
    }

    private func statusIcon(_ target: (min: Int, max: Int, status: String)) -> String {
        if setsCompleted < target.min { return "🎯" }
        else if setsCompleted <= target.max { return "✅" }
        else { return "⚠️" }
    }

    private func statusMessage(_ target: (min: Int, max: Int, status: String)) -> String {
        if setsCompleted < target.min { return "Approaching optimal volume" }
        else if setsCompleted <= target.max { return "Optimal range for growth" }
        else { return "High volume - watch recovery" }
    }
}
