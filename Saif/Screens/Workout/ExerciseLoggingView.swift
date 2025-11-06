import SwiftUI

struct ExerciseLoggingView: View {
    let exercise: Exercise
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss

    @State private var setNumber = 1
    @State private var reps = ""
    @State private var weight = ""
    @State private var goSummary = false
    @State private var nextInGroup = false
    @State private var goSuggestions = false
    @State private var showPlan = false
    @State private var currentRecommendation: WorkoutManager.SetRecommendation?
    @State private var logError: String? = nil
    @State private var rpeSelection: Int = 0 // 0 = none, else 6-10
    @State private var showChatbot = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                Text(exercise.name).font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                Text(exercise.muscleGroup.capitalized).foregroundStyle(SAIFColors.mutedText)

                // Volume progress tracking
                VolumeProgressCard(group: exercise.muscleGroup)

                if let rec = workoutManager.setRepRecommendation {
                    CardView(title: "AI Recommendation") {
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            HStack(spacing: SAIFSpacing.lg) {
                                Text("Reps: \(rec.reps)")
                                Text("Weight: \(Int(rec.weight))lbs")
                                Text("Rest: \(rec.restSeconds)s")
                            }
                            if !rec.notes.isEmpty {
                                Text(rec.notes)
                                    .font(.system(size: 12))
                                    .foregroundStyle(SAIFColors.mutedText)
                            }
                        }
                        .foregroundStyle(SAIFColors.text)
                    }
                }

                if let rec = currentRecommendation {
                    HStack(alignment: .top, spacing: SAIFSpacing.md) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(rec.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.message)
                                .font(.system(size: 14))
                                .foregroundStyle(SAIFColors.text)
                            if let adjustment = rec.suggestedAdjustment {
                                Text("Suggestion: \(adjustment)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(rec.color)
                                if rec.actionable {
                                    Button("Apply Suggestion") {
                                        applySuggestion(adjustment)
                                    }.buttonStyle(.bordered)
                                    Button("Ignore") { currentRecommendation = nil }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                        Spacer()
                        Button { currentRecommendation = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                    .padding(SAIFSpacing.md)
                    .background((currentRecommendation?.color ?? SAIFColors.mutedText).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: currentRecommendation?.message ?? "")
                }

                CardView(title: "Log Set #\(setNumber)") {
                    VStack(spacing: SAIFSpacing.md) {
                        HStack { Text("Reps"); Spacer(); TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Weight (lb)"); Spacer(); TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack {
                            Text("RPE (optional)")
                            Spacer()
                            Picker("RPE", selection: $rpeSelection) {
                                Text("—").tag(0)
                                Text("6").tag(6)
                                Text("7").tag(7)
                                Text("8").tag(8)
                                Text("9").tag(9)
                                Text("10").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 280)
                        }
                        PrimaryButton("Add Set") { Task { await addSetAsync() } }
                    }
                }

                HStack(spacing: SAIFSpacing.md) {
                    PrimaryButton("Finish Exercise", variant: .accent) { finishExercise() }
                    Button {
                        // Record adaptation and go pick another exercise
                        Task { await workoutManager.adaptPlan(exerciseId: exercise.id, reason: .userRequest, action: .substitutedExercise, notes: "User swapped exercise") }
                        nextInGroup = true
                    } label: {
                        HStack { Image(systemName: "arrow.2.squarepath"); Text("Swap Exercise") }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                NavigationLink(destination: ExerciseSelectionView(muscleGroup: exercise.muscleGroup).environmentObject(workoutManager), isActive: $nextInGroup) { EmptyView() }
                // Retired legacy next suggestions view
                EmptyView()
            }.padding(SAIFSpacing.xl)
            // Floating Ask Coach button
            VStack { Spacer()
                HStack { Spacer()
                    Button {
                        showChatbot = true
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "sparkles"); Text("Ask Coach") }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(SAIFColors.accent)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("Plan") { showPlan = true } }
            ToolbarItem(placement: .automatic) { Button("End") { goSummary = true } }
        }
        .sheet(isPresented: $showPlan) {
            if let plan = workoutManager.currentPlan { SessionPlanView(plan: plan).environmentObject(workoutManager) }
        }
        .sheet(isPresented: $showChatbot) {
            WorkoutChatbotView(context: .exerciseQuestion)
                .environmentObject(workoutManager)
        }
        .overlay(alignment: .top) {
            if let message = logError {
                HStack(spacing: SAIFSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                    Text(message).foregroundStyle(.white).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("Dismiss") { withAnimation { logError = nil } }
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
    }

    private func addSetAsync() async {
        // Validate inputs
        let repsVal = Int(reps) ?? 0
        let weightVal = Double(weight) ?? 0
        guard repsVal > 0 else { withAnimation { logError = "Please enter a valid reps count." }; return }
        guard weightVal >= 0 else { withAnimation { logError = "Weight cannot be negative." }; return }
        let sessionId = workoutManager.currentSession?.id ?? UUID()
        let rpeVal: Int? = (rpeSelection == 0 ? nil : rpeSelection)
        // Resolve exercise to a DB-backed record if needed to avoid FK errors
        var resolvedId = exercise.id
        var canPersistRemotely = false
        if let resolved = try? await SupabaseService.shared.getExerciseByName(name: exercise.name, muscleGroup: exercise.muscleGroup) {
            resolvedId = resolved.id
            canPersistRemotely = true
            await MainActor.run { workoutManager.currentExercise = resolved }
        }
        let set = ExerciseSet(id: UUID(), sessionId: sessionId, exerciseId: resolvedId, setNumber: setNumber, reps: repsVal, weight: weightVal, rpe: rpeVal, restSeconds: nil, completedAt: Date())
        workoutManager.completedSets.append(set)
        workoutManager.saveWorkoutState()
        // Persist to Supabase only if we have a DB exercise id
        do {
            if canPersistRemotely {
                _ = try await SupabaseService.shared.logExerciseSet(set)
            }
        } catch {
            print("❌ [ExerciseLoggingView.addSet] failed: \(error)")
            let ns = error as NSError
            await MainActor.run {
                if ns.domain == NSURLErrorDomain {
                    withAnimation { logError = "Network error while saving set. It will remain local." }
                } else {
                    withAnimation { logError = "Failed to save set. It will remain local." }
                }
            }
        }
        setNumber += 1
        reps = ""; weight = ""

        // Analyze performance for coaching feedback
        var targetMin = 8
        var targetMax = 12
        if let plan = workoutManager.currentPlan,
           let plannedEx = plan.exercises.first(where: { $0.exerciseId == exercise.id }) ?? plan.exercises.first(where: { $0.exerciseName == exercise.name }) {
            targetMin = plannedEx.targetRepsMin
            targetMax = plannedEx.targetRepsMax
        } else if let lm = workoutManager.volumeLandmarks(for: exercise.muscleGroup) {
            // Parse landmarks.repRange like "6-12 reps"
            let txt = TextSanitizer.sanitizedResearchText(lm.repRange)
            let nums = txt.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 { targetMin = nums[0]; targetMax = nums[1] }
        }
        currentRecommendation = workoutManager.analyzeSetPerformance(
            exercise: exercise,
            setNumber: workoutManager.completedSets.filter { $0.exerciseId == exercise.id }.count,
            weight: weightVal,
            reps: repsVal,
            rpe: rpeVal,
            targetRepsMin: targetMin,
            targetRepsMax: targetMax
        )
    }

    private func applySuggestion(_ adjustment: String) {
        // Parse strings like "+10 lbs" or "-5 lbs"
        let trimmed = adjustment.replacingOccurrences(of: "lbs", with: "").trimmingCharacters(in: .whitespaces)
        let sign: Double = trimmed.hasPrefix("-") ? -1 : 1
        let numberPart = trimmed.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
        if let delta = Double(numberPart) {
            let current = Double(weight) ?? 0
            let next = max(0, current + sign * delta)
            weight = String(Int(round(next)))
        }
    }

    private func finishExercise() {
        // mark exercise completed
        let exForCompletion = workoutManager.currentExercise ?? exercise
        workoutManager.markExerciseCompleted(exerciseId: exForCompletion.id, group: exForCompletion.muscleGroup)
        Task { await workoutManager.markExerciseCompleteInPlan(for: exForCompletion) }
        // Return to the plan sheet on the Current tab for next selection
        workoutManager.sessionPlanPreferredTab = 1
        showPlan = true
        workoutManager.saveWorkoutState()
    }
}

#Preview { NavigationStack { ExerciseLoggingView(exercise: Exercise(id: UUID(), name: "Bench Press", muscleGroup: "chest", workoutType: "push", equipment: [], difficulty: .beginner, isCompound: true, description: "", formCues: [])).environmentObject(WorkoutManager()) } }

// MARK: - Volume Progress Card
private struct VolumeProgressCard: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    let group: String

    private func parseUpperBound(from range: String) -> Int? {
        // Handles formats like "8-10" or "8–10" or "8 to 10"
        let digits = range.replacingOccurrences(of: "to", with: "-").replacingOccurrences(of: "–", with: "-")
        let parts = digits.split(separator: "-")
        if let last = parts.last, let val = Int(last.filter({ $0.isNumber })) { return val }
        return Int(digits.filter({ $0.isNumber }))
    }

    var body: some View {
        let today = workoutManager.setsCompletedToday(for: group)
        let landmarks = workoutManager.volumeLandmarks(for: group)
        let sessionRange = workoutManager.targetSetsRange
        let sessionCap = sessionRange.flatMap(parseUpperBound)
        return AnyView(
            Group {
                if landmarks != nil || sessionRange != nil {
                    CardView(title: "Volume Progress") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let cap = sessionCap {
                                Text("📊 \(group.capitalized) Volume Today: \(today)/\(cap) sets")
                            } else {
                                Text("📊 \(group.capitalized) Volume Today: \(today) sets")
                            }
                            if let s = sessionRange { Text("Target this session: \(s) sets") }
                            if let lm = landmarks {
                                Text("Target: \(TextSanitizer.sanitizedResearchText(lm.mav)) (MAV range)")
                                Text("\(TextSanitizer.sanitizedResearchText(lm.frequencyRecommendation))")
                                    .foregroundStyle(SAIFColors.mutedText)
                            }
                        }
                        .foregroundStyle(SAIFColors.text)
                    }
                }
            }
        )
    }
}
