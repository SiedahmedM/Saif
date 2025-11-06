import SwiftUI

struct SessionPlanView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss
    let plan: SessionPlan

    @State private var selectedMuscleGroup: String
    @State private var showExerciseLibrary = false
    @State private var exerciseToReplace: SessionPlan.PlannedExercise?
    // Logging presentation (sheet-based to avoid NavigationLink edge cases)
    @State private var showLogging = false
    @State private var planError: String? = nil
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var planTab: Int = 0
    @State private var showEdit = false
    @State private var editSet: ExerciseSet? = nil
    @State private var editReps: String = ""
    @State private var editWeight: String = ""
    @State private var confirmDeleteSetId: UUID? = nil
    @State private var showDeleteAlert = false
    @State private var showPostSummary = false
    @State private var showEndConfirm = false
    @State private var showChatbot = false

    init(plan: SessionPlan) {
        self.plan = plan
        self._selectedMuscleGroup = State(initialValue: plan.muscleGroups.first ?? "")
    }

    private var activePlan: SessionPlan { workoutManager.currentPlan ?? plan }
    private var exercisesForSelectedGroup: [SessionPlan.PlannedExercise] {
        activePlan.exercises.filter { $0.muscleGroup == selectedMuscleGroup }
    }

    var body: some View {
        ZStack { Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    // Header
                    VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                        Text("Your Workout Plan")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(activePlan.workoutType.capitalized) • \(activePlan.estimatedDuration) minutes")
                            .foregroundStyle(.white.opacity(0.8))
                        Text(activePlan.muscleGroups.map { $0.capitalized }.joined(separator: ", "))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SAIFColors.primary)
                    }

                    Picker("Mode", selection: $planTab) {
                        Text("Plan").tag(0)
                        Text("Current").tag(1)
                    }
                    .pickerStyle(.segmented)

                    // Safety Notes
                    if planTab == 0, !activePlan.safetyNotes.isEmpty {
                        VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                            HStack(spacing: SAIFSpacing.sm) {
                                Image(systemName: "shield.checkered").foregroundStyle(.orange)
                                Text("Important Notes")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                                ForEach(activePlan.safetyNotes, id: \.self) { note in
                                    HStack(alignment: .top, spacing: SAIFSpacing.md) {
                                        Text(icon(for: note)).font(.system(size: 24))
                                        Text(cleanNote(note))
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(SAIFSpacing.lg)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SAIFRadius.lg)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    if planTab == 0 {
                    VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                        HStack(spacing: SAIFSpacing.sm) {
                            Image(systemName: "chart.bar.fill").foregroundStyle(.white)
                            Text("Volume Targets Today")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(spacing: SAIFSpacing.lg) {
                            ForEach(activePlan.volumeTargets) { t in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(t.muscleGroup.capitalized)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("\(t.targetSetsToday) sets")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(SAIFColors.primary)
                                    }
                                    Text(t.reasoning)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.8))
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 10)
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(SAIFColors.primary)
                                                .frame(width: geo.size.width * (Double(t.completedThisWeek) / Double(max(t.weeklyTarget, 1))), height: 10)
                                        }
                                    }
                                    .frame(height: 10)
                                    HStack {
                                        Spacer()
                                        Text("\(t.completedThisWeek)/\(t.weeklyTarget) this week")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                }
                                .padding(SAIFSpacing.lg)
                                .background(
                                    LinearGradient(
                                        colors: [Color(white: 0.15), Color(white: 0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                                .overlay(
                                    RoundedRectangle(cornerRadius: SAIFRadius.lg)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                    }

                    if planTab == 0 {
                    // Workout Summary
                    VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                        HStack(spacing: SAIFSpacing.sm) {
                            Image(systemName: "list.bullet.rectangle").foregroundStyle(.white)
                            Text("Workout Summary")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("Review and customize your exercises")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SAIFSpacing.sm) {
                                ForEach(activePlan.muscleGroups, id: \.self) { group in
                                    MuscleGroupTab(
                                        name: group,
                                        isSelected: selectedMuscleGroup == group,
                                        exerciseCount: activePlan.exercises.filter { $0.muscleGroup == group }.count
                                    ) {
                                        withAnimation(.spring(response: 0.3)) { selectedMuscleGroup = group }
                                    }
                                }
                            }
                        }
                        VStack(spacing: SAIFSpacing.md) {
                            ForEach(Array(exercisesForSelectedGroup.enumerated()), id: \.element.id) { idx, ex in
                                SwappableExerciseCard(
                                    exercise: ex,
                                    onSwap: {
                                        exerciseToReplace = ex
                                        showExerciseLibrary = true
                                    },
                                    onMoveUp: {
                                        Task {
                                            let ok = await workoutManager.movePlannedExercise(plannedId: ex.id, inGroup: selectedMuscleGroup, moveUp: true)
                                            if ok {
                                                withAnimation { toastMessage = "✓ Updated"; showToast = true }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showToast = false } }
                                            } else {
                                                withAnimation { planError = "Failed to reorder exercise. Please try again." }
                                                print("❌ [movePlannedExercise] failed: could not move up")
                                            }
                                        }
                                    },
                                    onMoveDown: {
                                        Task {
                                            let ok = await workoutManager.movePlannedExercise(plannedId: ex.id, inGroup: selectedMuscleGroup, moveUp: false)
                                            if ok {
                                                withAnimation { toastMessage = "✓ Updated"; showToast = true }
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showToast = false } }
                                            } else {
                                                withAnimation { planError = "Failed to reorder exercise. Please try again." }
                                                print("❌ [movePlannedExercise] failed: could not move down")
                                            }
                                        }
                                    },
                                    canMoveUp: idx > 0,
                                    canMoveDown: idx < exercisesForSelectedGroup.count - 1
                                )
                            }
                        }
                    }
                    }

                    if planTab == 1 {
                        // Current: Completed today + Up Next
                        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                            HStack(spacing: SAIFSpacing.sm) {
                                Image(systemName: "list.bullet.rectangle").foregroundStyle(.white)
                                Text("Up Next")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            // Completed Today
                            if !workoutManager.completedSets.isEmpty {
                                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                    Text("Completed Today").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                                    let grouped = Dictionary(grouping: workoutManager.completedSets, by: { $0.exerciseId })
                                    ForEach(activePlan.exercises.filter { $0.isCompleted }) { p in
                                        let sets = grouped[p.exerciseId ?? UUID()] ?? []
                                        if !sets.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(spacing: 8) {
                                                    Text(p.exerciseName).font(.system(size: 16, weight: .semibold)).foregroundStyle(.green)
                                                    Text("Completed").font(.system(size: 11, weight: .bold)).foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 2).background(Color.green.opacity(0.15)).clipShape(Capsule())
                                                    Spacer()
                                                    Button("Add Set") {
                                                        Task {
                                                            print("➕ [SessionPlan] Add Set for: \(p.exerciseName)")
                                                            if let eid = p.exerciseId, let db = try? await SupabaseService.shared.getExerciseById(eid) {
                                                                await MainActor.run { workoutManager.currentExercise = db; showLogging = true }
                                                            } else if let db = try? await SupabaseService.shared.getExerciseByName(name: p.exerciseName, muscleGroup: p.muscleGroup) {
                                                                await MainActor.run { workoutManager.currentExercise = db; showLogging = true }
                                                            } else {
                                                                print("⚠️ [SessionPlan] Add Set resolve failed for \(p.exerciseName)")
                                                                await MainActor.run { planError = "Couldn’t open logging for \(p.exerciseName). Please try again." }
                                                            }
                                                        }
                                                    }
                                                    .buttonStyle(.borderedProminent)
                                                }
                                                ForEach(sets.sorted(by: { $0.setNumber < $1.setNumber })) { s in
                                                    HStack(spacing: 8) {
                                                        Text("Set \(s.setNumber)").font(.system(size: 12, weight: .bold)).foregroundStyle(s.setNumber == 1 ? .green : .white)
                                                        Text("Reps: \(s.reps)").font(.system(size: 12)).foregroundStyle(.white)
                                                        Text("Weight: \(Int(s.weight))").font(.system(size: 12)).foregroundStyle(.white)
                                                        Spacer()
                                                        Button("Edit") {
                                                            editSet = s; editReps = String(s.reps); editWeight = String(Int(s.weight)); showEdit = true
                                                        }.font(.system(size: 12)).buttonStyle(.bordered)
                                                        Button("Delete") {
                                                            confirmDeleteSetId = s.id; showDeleteAlert = true
                                                        }.font(.system(size: 12)).foregroundStyle(.red)
                                                    }
                                                }
                                            }
                                            .padding()
                                            .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                                            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                        }
                                    }
                                }
                            }
                            VStack(spacing: SAIFSpacing.sm) {
                                let pending = activePlan.exercises.sorted { $0.orderIndex < $1.orderIndex }.filter { !$0.isCompleted }
                                ForEach(pending) { ex in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(ex.exerciseName).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                            Text(ex.muscleGroup.capitalized).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                                        }
                                        Spacer()
                                        Button {
                                            Task {
                                                HapticsService.light()
                                                print("▶️ [SessionPlan] Start tapped for: \(ex.exerciseName) in \(ex.muscleGroup)")
                                                if let db = try? await SupabaseService.shared.getExerciseByName(name: ex.exerciseName, muscleGroup: ex.muscleGroup) {
                                                    print("✅ [SessionPlan] Resolved DB exercise: \(db.name) → opening logging sheet")
                                                    await MainActor.run { workoutManager.currentExercise = db; showLogging = true }
                                                } else {
                                                    print("⚠️ [SessionPlan] DB resolve failed for \(ex.exerciseName). Using fallback and navigating")
                                                    let fallback = Exercise(id: UUID(), name: ex.exerciseName, muscleGroup: ex.muscleGroup, workoutType: activePlan.workoutType, equipment: [], difficulty: .beginner, isCompound: ex.isCompound, description: "", formCues: [])
                                                    await MainActor.run { workoutManager.currentExercise = fallback; showLogging = true }
                                                }
                                            }
                                        } label: {
                                            Text("Start").font(.system(size: 13, weight: .semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding()
                                    .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                }
                                // End Workout action on Current tab
                                HStack {
                                    Spacer()
                                    Button {
                                        showEndConfirm = true
                                    } label: {
                                        HStack { Image(systemName: "stop.circle.fill"); Text("End Workout") }
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Spacer()
                                }
                                .padding(.top, SAIFSpacing.md)
                            }
                        }
                    }

                    // Start button (only on Plan tab)
                    if planTab == 0 { PrimaryButton("Start Workout") { startFirstExercise() } }
                    Spacer(minLength: 20)
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .sheet(isPresented: $showLogging) {
            if let ex = workoutManager.currentExercise {
                NavigationStack { ExerciseLoggingView(exercise: ex).environmentObject(workoutManager) }
            } else { EmptyView() }
        }
        .onAppear {
            // Sync initial tab state with manager preference
            planTab = workoutManager.sessionPlanPreferredTab
        }
        .onChange(of: planTab) { _, newVal in
            workoutManager.sessionPlanPreferredTab = newVal
        }
        .onChange(of: workoutManager.currentExercise?.id) { _, newVal in
            if newVal != nil {
                print("➡️ [SessionPlan] currentExercise set; presenting logging sheet")
                showLogging = true
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                Form {
                    Section("Edit Set") {
                        TextField("Reps", text: $editReps).keyboardType(.numberPad)
                        TextField("Weight", text: $editWeight).keyboardType(.decimalPad)
                        if let s = editSet {
                            Button("Add Another Set") {
                                Task {
                                    guard let session = workoutManager.currentSession else { showEdit = false; return }
                                    let reps = Int(editReps) ?? s.reps
                                    let weight = Double(editWeight) ?? s.weight
                                    let nextNum = (workoutManager.completedSets.filter { $0.exerciseId == s.exerciseId }.map { $0.setNumber }.max() ?? s.setNumber) + 1
                                    let newSet = ExerciseSet(id: UUID(), sessionId: session.id, exerciseId: s.exerciseId, setNumber: nextNum, reps: reps, weight: weight, rpe: s.rpe, restSeconds: nil, completedAt: Date())
                                    workoutManager.completedSets.append(newSet)
                                    workoutManager.saveWorkoutState()
                                    do { _ = try await SupabaseService.shared.logExerciseSet(newSet) } catch { print("❌ [AddAnotherSet] failed: \(error)") }
                                    showEdit = false
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Edit Set")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showEdit = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let s = editSet, let r = Int(editReps), let w = Double(editWeight) {
                                Task { await workoutManager.updateLoggedSet(setId: s.id, reps: r, weight: w, rpe: s.rpe); showEdit = false }
                            } else { showEdit = false }
                        }
                    }
                }
            }
        }
        .alert("Delete Set?", isPresented: $showDeleteAlert, presenting: confirmDeleteSetId) { id in
            Button("Delete", role: .destructive) { Task { await workoutManager.deleteLoggedSet(setId: id) } }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This will remove the set from today's workout. You can’t undo.")
        }
        .alert("End Workout?", isPresented: $showEndConfirm) {
            Button("End", role: .destructive) { showPostSummary = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can review and save in the summary screen.")
        }
        .sheet(isPresented: $showPostSummary) {
            NavigationStack { PostWorkoutSummaryView().environmentObject(workoutManager) }
        }
        // After summary saves, close this plan view so user returns to previous screen (Start/Home).
        .onReceive(NotificationCenter.default.publisher(for: .saifWorkoutCompleted)) { _ in
            showPostSummary = false
            dismiss()
        }
        .overlay(alignment: .top) {
            if let message = planError {
                HStack(spacing: SAIFSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                    Text(message).foregroundStyle(.white).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Dismiss") { withAnimation { planError = nil } }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, SAIFSpacing.lg)
                .padding(.vertical, SAIFSpacing.sm)
                .background(Color.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                .padding(.horizontal, SAIFSpacing.xl)
                .padding(.top, SAIFSpacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SAIFSpacing.lg)
                    .padding(.vertical, SAIFSpacing.sm)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showExerciseLibrary) {
            if let ex = exerciseToReplace {
                ExerciseLibrarySheet(muscleGroup: ex.muscleGroup, workoutType: activePlan.workoutType) { newExercise in
                    Task {
                        let ok = await workoutManager.replaceExerciseInPlan(old: ex, new: newExercise)
                        if ok {
                            withAnimation { toastMessage = "✓ Updated"; showToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { showToast = false } }
                        } else {
                            withAnimation { planError = "Failed to swap exercise. Please try again." }
                            print("❌ [replaceExerciseInPlan] failed: swap did not complete")
                        }
                        showExerciseLibrary = false
                    }
                }
            }
        }
        .navigationTitle("Your Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showChatbot = true } label: {
                    Image(systemName: "message.circle.fill")
                        .foregroundStyle(SAIFColors.accent)
                }
                .accessibilityLabel("Ask Coach")
            }
        }
        .sheet(isPresented: $showChatbot) {
            WorkoutChatbotView(context: .planReview)
                .environmentObject(workoutManager)
        }
    }

    private func startFirstExercise() {
        let list = activePlan.exercises
        guard let first = list.first else { return }
        Task {
            do {
                if let exercise = try await SupabaseService.shared.getExerciseByName(name: first.exerciseName, muscleGroup: first.muscleGroup) {
                    await MainActor.run {
                        workoutManager.currentExercise = exercise
                        showLogging = true
                    }
                } else {
                    // Fallback when not found
                    let fallback = Exercise(
                        id: UUID(),
                        name: first.exerciseName,
                        muscleGroup: first.muscleGroup,
                        workoutType: plan.workoutType,
                        equipment: [],
                        difficulty: .beginner,
                        isCompound: first.isCompound,
                        description: "",
                        formCues: []
                    )
                    await MainActor.run {
                        print("❌ [startFirstExercise] failed: Not found in DB — using fallback \(first.exerciseName)")
                        planError = "Failed to load exercise info. Using fallback."
                        workoutManager.currentExercise = fallback
                        showLogging = true
                    }
                }
            } catch {
                // Network or other error
                await MainActor.run {
                    print("❌ [startFirstExercise] failed: \(error)")
                    if (error as NSError).domain == NSURLErrorDomain {
                        planError = "Network error. Please check your connection."
                    } else {
                        planError = "Failed to start workout. Please try again."
                    }
                    // Gracefully degrade with fallback so user can proceed
                    let fallback = Exercise(
                        id: UUID(),
                        name: first.exerciseName,
                        muscleGroup: first.muscleGroup,
                        workoutType: plan.workoutType,
                        equipment: [],
                        difficulty: .beginner,
                        isCompound: first.isCompound,
                        description: "",
                        formCues: []
                    )
                    workoutManager.currentExercise = fallback
                    showLogging = true
                }
            }
        }
    }

    // MARK: - Helpers (Safety Notes)
    private func icon(for note: String) -> String {
        if note.contains("⚠️") { return "⚠️" }
        if note.contains("💪") { return "💪" }
        if note.contains("🏋️") { return "🏋️" }
        return "ℹ️"
    }
    private func cleanNote(_ note: String) -> String {
        note
            .replacingOccurrences(of: "⚠️ ", with: "")
            .replacingOccurrences(of: "💪 ", with: "")
            .replacingOccurrences(of: "🏋️ ", with: "")
    }
}

struct MuscleGroupTab: View {
    let name: String
    let isSelected: Bool
    let exerciseCount: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(name.capitalized)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                Text("\(exerciseCount) ex")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .white.opacity(0.6))
            }
            .padding(.vertical, SAIFSpacing.sm)
            .padding(.horizontal, SAIFSpacing.md)
            .background(isSelected ? SAIFColors.primary : Color(white: 0.15))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
        }
    }
}

struct SwappableExerciseCard: View {
    let exercise: SessionPlan.PlannedExercise
    let onSwap: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Label("\(exercise.targetSets) sets", systemImage: "number"); Text("•"); Label("\(exercise.targetRepsMin)-\(exercise.targetRepsMax)", systemImage: "arrow.up.arrow.down")
                        if exercise.isCompound {
                            Text("COMPOUND").font(.system(size: 9, weight: .bold)).foregroundStyle(SAIFColors.primary).padding(.horizontal, 4).padding(.vertical, 2).background(SAIFColors.primary.opacity(0.1)).clipShape(Capsule())
                        }
                    }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: SAIFSpacing.sm) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canMoveUp ? .white : .white.opacity(0.3))
                    }
                    .disabled(!canMoveUp)
                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canMoveDown ? .white : .white.opacity(0.3))
                    }
                    .disabled(!canMoveDown)
                    Button(action: onSwap) {
                        HStack(spacing: 4) { Image(systemName: "arrow.2.squarepath").font(.system(size: 12)); Text("Swap").font(.system(size: 13, weight: .medium)) }
                            .foregroundStyle(SAIFColors.primary)
                            .padding(.horizontal, SAIFSpacing.md)
                            .padding(.vertical, SAIFSpacing.sm)
                            .background(SAIFColors.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            if !exercise.rationale.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 10)).foregroundStyle(SAIFColors.accent)
                    Text(exercise.rationale).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
            }
        }
        .padding(SAIFSpacing.md)
        .background(
            LinearGradient(colors: [Color(white: 0.15), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct ExerciseLibrarySheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutManager: WorkoutManager
    let muscleGroup: String
    let workoutType: String
    let onSelect: (Exercise) -> Void
    @State private var exercises: [Exercise] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorMessage {
                    VStack(spacing: SAIFSpacing.md) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.white)
                        Text(err).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadExercises() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if exercises.isEmpty {
                    VStack(spacing: SAIFSpacing.md) {
                        Image(systemName: "dumbbell").font(.system(size: 48)).foregroundStyle(.white.opacity(0.6))
                        Text("No exercises found").foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: SAIFSpacing.sm) {
                            ForEach(exercises) { ex in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(ex.name).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                                            if workoutManager.isAvoided(ex.id) { Text("Avoided").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange) }
                                            if workoutManager.isFavorite(ex.id) { Text("Favorite").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red) }
                                        }
                                        HStack(spacing: 6) {
                                            if ex.isCompound { Text("Compound").font(.system(size: 12)).foregroundStyle(SAIFColors.primary) }
                                            Text(ex.equipment.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        Task {
                                            let fav = workoutManager.isFavorite(ex.id)
                                            await workoutManager.setExercisePreference(exerciseId: ex.id, level: fav ? .neutral : .favorite, reason: nil)
                                        }
                                    } label: {
                                        Image(systemName: workoutManager.isFavorite(ex.id) ? "heart.fill" : "heart")
                                            .foregroundStyle(workoutManager.isFavorite(ex.id) ? .red : .white.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                                        // present preference sheet using SessionPlanView's sheet
                                        // fallback: no-op here; preference via tap above
                                    })
                                    Button { onSelect(ex) } label: {
                                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .padding()
                                .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                        }
                        .padding(SAIFSpacing.xl)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("\(muscleGroup.capitalized) Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await loadExercises() }
        }
    }
    private func loadExercises() async {
        isLoading = true
        errorMessage = nil
        do {
            exercises = try await SupabaseService.shared.getExercisesByMuscleGroup(workoutType: workoutType, muscleGroup: muscleGroup)
        } catch {
            print("❌ [ExerciseLibrarySheet.loadExercises] failed: \(error)")
            if (error as NSError).domain == NSURLErrorDomain {
                errorMessage = "Network error. Please check your connection and try again."
            } else {
                errorMessage = "Failed to load exercises. Please try again."
            }
        }
        isLoading = false
    }
}
