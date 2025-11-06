import SwiftUI

struct WorkoutChatbotView: View {
    enum ChatContext {
        case planReview
        case exerciseQuestion
        case formCheck
        case general
    }

    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss
    let context: ChatContext

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var restCountdown: Int? = nil
    @State private var restTimer: Timer? = nil
    @State private var coachTone: String = UserDefaults.standard.string(forKey: "coach_tone") ?? "brief"
    @State private var errorBanner: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let e = errorBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                        Text(e).foregroundStyle(.white).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                        Button("Dismiss") { withAnimation { errorBanner = nil } }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, SAIFSpacing.lg)
                    .padding(.vertical, SAIFSpacing.sm)
                    .background(Color.red.opacity(0.85))
                }

                // Rest timer banner
                if let secs = restCountdown, secs > 0 {
                    HStack(spacing: SAIFSpacing.sm) {
                        Image(systemName: "timer")
                        Text("Rest: \(secs)s remaining")
                        Spacer()
                        Button("Cancel") { cancelRestTimer() }
                    }
                    .padding(.horizontal, SAIFSpacing.lg)
                    .padding(.vertical, SAIFSpacing.sm)
                    .background(Color.orange.opacity(0.15))
                }

                // Chat messages
                ScrollView {
                    VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }
                        if isLoading {
                            HStack(spacing: SAIFSpacing.sm) {
                                ProgressView()
                                Text("Coach is thinking...")
                                    .foregroundStyle(SAIFColors.mutedText)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }

                // Quick questions
                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                    Text("Quick Questions:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SAIFColors.mutedText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SAIFSpacing.sm) {
                            QuickQuestionButton("How's my form?") { inputText = $0; sendMessage() }
                            QuickQuestionButton("Should I increase weight?") { inputText = $0; sendMessage() }
                            QuickQuestionButton("What's a good substitute?") { inputText = $0; sendMessage() }
                            QuickQuestionButton("Am I training enough?") { inputText = $0; sendMessage() }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, SAIFSpacing.sm)

                // Input field
                HStack(spacing: SAIFSpacing.sm) {
                    TextField("Ask your coach anything...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(SAIFColors.primary)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding()
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { addContextualGreeting() }
        }
    }

    private func addContextualGreeting() {
        let greeting: String
        switch context {
        case .planReview:
            greeting = "Hi! I see you're reviewing your workout plan. Want to make changes or have questions about exercises?"
        case .exerciseQuestion:
            if let currentEx = workoutManager.currentExercise {
                greeting = "I'm here to help with \(currentEx.name). Need form tips or have questions?"
            } else { greeting = "How can I help with your workout?" }
        case .formCheck:
            greeting = "Let me help with your form! What exercise are you working on?"
        case .general:
            greeting = "Hey! How can I assist you today?"
        }
        messages.append(ChatMessage(id: UUID(), role: .assistant, content: greeting, timestamp: Date()))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(ChatMessage(id: UUID(), role: .user, content: text, timestamp: Date()))
        isLoading = true
        errorBanner = nil

        Task {
            do {
                let ctx = buildWorkoutContext()
                let reply = try await OpenAIService.shared.chatWithContextJSON(message: text, context: ctx, conversationHistory: messages, tone: coachTone)
                await MainActor.run {
                    renderCoachReply(reply)
                    isLoading = false
                }
            } catch {
                print("❌ [WorkoutChatbotView.sendMessage] \(error)")
                await MainActor.run {
                    // Fallback: try rule-based tip
                    let fallback = ruleBasedFallback()
                    messages.append(ChatMessage(id: UUID(), role: .assistant, content: fallback, timestamp: Date()))
                    if (error as NSError).domain == NSURLErrorDomain {
                        errorBanner = "Network error. Please check your connection."
                    } else {
                        errorBanner = "AI service error. Please try again later."
                    }
                    isLoading = false
                }
            }
        }
    }

    private func buildWorkoutContext() -> String {
        var context = "Current workout context:\n"
        if let session = workoutManager.currentSession {
            context += "- Workout type: \(session.workoutType)\n"
            context += "- Time elapsed: \(Int(Date().timeIntervalSince(session.startedAt) / 60)) minutes\n"
        }
        if let plan = workoutManager.currentPlan {
            context += "- Total exercises planned: \(plan.exercises.count)\n"
            context += "- Muscle groups: \(plan.muscleGroups.joined(separator: ", "))\n"
        }
        if let currentEx = workoutManager.currentExercise {
            context += "- Current exercise: \(currentEx.name)\n"
            context += "- Muscle group: \(currentEx.muscleGroup)\n"
            // Last 3 sets for current exercise
            let sets = workoutManager.completedSets.filter { $0.exerciseId == currentEx.id }.sorted { $0.setNumber > $1.setNumber }.prefix(3)
            if !sets.isEmpty {
                context += "- Recent sets: [" + sets.map { "{reps:\($0.reps),weight:\(Int($0.weight)),rpe:\($0.rpe ?? 0)}" }.joined(separator: ", ") + "]\n"
                if let last = sets.first { // e1RM (Epley)
                    let e1rm = last.weight * (1.0 + Double(last.reps)/30.0)
                    context += String(format: "- Estimated 1RM: %.0f lb\n", e1rm)
                }
            }
            // Rest elapsed since last set
            if let last = workoutManager.completedSets.filter({ $0.exerciseId == currentEx.id }).max(by: { $0.completedAt < $1.completedAt }) {
                let secs = Int(Date().timeIntervalSince(last.completedAt))
                context += "- Rest elapsed: \(secs)s\n"
            }
        }
        // Plan targets and Up Next
        if let plan = workoutManager.currentPlan, let ex = workoutManager.currentExercise,
           let planned = plan.exercises.first(where: { ($0.exerciseId == ex.id) || ($0.exerciseName.lowercased() == ex.name.lowercased()) }) {
            context += "- Target reps: \(planned.targetRepsMin)-\(planned.targetRepsMax)\n"
        }
        if let plan = workoutManager.currentPlan {
            let pending = plan.exercises.filter { !$0.isCompleted }.map { $0.exerciseName }.prefix(5)
            if !pending.isEmpty { context += "- Up Next: \(pending.joined(separator: ", "))\n" }
        }

        // Constraints: preferences and injuries
        let favs = workoutManager.exercisePreferences.filter { $0.preferenceLevel == .favorite }.count
        let avoids = workoutManager.exercisePreferences.filter { $0.preferenceLevel == .avoid }.count
        context += "- Preferences: \(favs) favorites, \(avoids) avoids\n"
        if let snap = workoutManager.profileSnapshot() {
            context += "- Goal: \(snap.goal.rawValue), Experience: \(snap.fitness.rawValue), Gym: \(snap.gym.rawValue)\n"
            if !snap.injuries.isEmpty { context += "- Injuries: \(snap.injuries.joined(separator: ", "))\n" }
        }
        // Research hints for current group
        if let ex = workoutManager.currentExercise,
           let lm = workoutManager.volumeLandmarks(for: ex.muscleGroup) {
            let rep = TextSanitizer.sanitizedResearchText(lm.repRange)
            let rest = TextSanitizer.sanitizedResearchText(lm.restBetweenSets)
            let intensity = TextSanitizer.sanitizedResearchText(lm.intensityGuidance)
            context += "- Research: rep_range=\(rep), rest=\(rest), intensity=\(intensity)\n"
        }
        context += "- Sets completed today: \(workoutManager.completedSets.count)\n"
        return context
    }

    private func renderCoachReply(_ reply: CoachResponse) {
        // Show summary + cues
        var text = reply.summary
        if !reply.cues.isEmpty { text += "\n• " + reply.cues.joined(separator: "\n• ") }
        messages.append(ChatMessage(id: UUID(), role: .assistant, content: text, timestamp: Date()))

        // Execute tool actions if present
        if let tool = reply.toolCall {
            handleToolCall(tool)
        } else if let action = reply.action {
            // Soft action suggestion: rest timer or simple keep/increase/decrease
            switch action.type {
            case .rest:
                let secs = max(action.seconds ?? 120, 60)
                startRestTimer(seconds: secs)
            default: break
            }
        }
        // Offer next question button (UX hint)
        if !reply.nextQuestion.isEmpty {
            messages.append(ChatMessage(id: UUID(), role: .assistant, content: "Next: \(reply.nextQuestion)", timestamp: Date()))
        }
    }

    private func startRestTimer(seconds: Int) { cancelRestTimer(); restCountdown = seconds; restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if let left = restCountdown, left > 0 { restCountdown = left - 1 } else { t.invalidate(); restTimer = nil }
        }
    }
    private func cancelRestTimer() { restTimer?.invalidate(); restTimer = nil; restCountdown = nil }

    private func ruleBasedFallback() -> String {
        // Use last set + volume landmarks for a minimal tip
        guard let ex = workoutManager.currentExercise else { return "Please try again in a moment." }
        let last = workoutManager.completedSets.filter { $0.exerciseId == ex.id }.max(by: { $0.setNumber < $1.setNumber })
        let lm = workoutManager.volumeLandmarks(for: ex.muscleGroup)
        if let s = last, let lm {
            return "Tip: Aim \(lm.repRange). You did \(s.reps) reps at \(Int(s.weight)) lb. If it felt easy, add a small increment (\(workoutManager.recommendedIncrementStep(for: ex)) lb)."
        }
        return "Focus on solid form. Ask about substitutions or rep targets."
    }

    // Handle tool calls from the model
    private func handleToolCall(_ tool: ToolCall) {
        switch tool.name {
        case .setRestTimer:
            let secs = max((tool.params["seconds"]?.raw as? Int) ?? 120, 60)
            startRestTimer(seconds: secs)
        case .updatePreference:
            if let ex = workoutManager.currentExercise, let level = tool.params["level"]?.raw as? String {
                Task { await workoutManager.setExercisePreference(exerciseId: ex.id, level: ExercisePreference.PreferenceLevel(rawValue: level) ?? .neutral, reason: nil) }
            }
        case .swapExercise:
            if let oldName = tool.params["oldName"]?.raw as? String, let newName = tool.params["newName"]?.raw as? String, let plan = workoutManager.currentPlan {
                if let old = plan.exercises.first(where: { $0.exerciseName.lowercased().contains(oldName.lowercased()) }) {
                    Task {
                        if let db = try? await SupabaseService.shared.getExerciseByName(name: newName, muscleGroup: old.muscleGroup) {
                            _ = await workoutManager.replaceExerciseInPlan(old: old, new: db)
                        }
                    }
                }
            }
        case .logSet:
            if let ex = workoutManager.currentExercise, let reps = tool.params["reps"]?.raw as? Int, let weightAny = tool.params["weight"]?.raw {
                let weight: Double
                if let d = weightAny as? Double { weight = d }
                else if let i = weightAny as? Int { weight = Double(i) }
                else { break }
                Task {
                    let nextNum = (workoutManager.completedSets.filter { $0.exerciseId == ex.id }.map { $0.setNumber }.max() ?? 0) + 1
                    let sessionId = workoutManager.currentSession?.id ?? UUID()
                    let set = ExerciseSet(id: UUID(), sessionId: sessionId, exerciseId: ex.id, setNumber: nextNum, reps: reps, weight: weight, rpe: nil, restSeconds: nil, completedAt: Date())
                    workoutManager.completedSets.append(set)
                    workoutManager.saveWorkoutState()
                    do { _ = try await SupabaseService.shared.logExerciseSet(set) } catch { print("❌ [Coach.logSet] \(error)") }
                }
            }
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: String, Codable { case user, assistant }
}

// Structured coach response models
struct CoachResponse: Codable {
    let summary: String
    let cues: [String]
    let action: CoachAction?
    let riskFlags: [String]?
    let nextQuestion: String
    let toolCall: ToolCall?

    enum CodingKeys: String, CodingKey {
        case summary, cues, action
        case riskFlags = "risk_flags"
        case nextQuestion = "next_question"
        case toolCall = "tool_call"
    }
}

struct CoachAction: Codable {
    enum ActionType: String, Codable { case increase_load, decrease_load, keep, rest, substitute }
    let type: ActionType
    let deltaLb: Int?
    let seconds: Int?

    enum CodingKeys: String, CodingKey { case type; case deltaLb = "delta_lb"; case seconds }
}

struct ToolCall: Codable {
    enum ToolName: String, Codable { case swapExercise, setRestTimer, logSet, updatePreference }
    let name: ToolName
    let params: [String: CodableValue]
}

// Codable heterogenous values for tool params
enum CodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var raw: Any {
        switch self { case .string(let s): return s; case .int(let i): return i; case .double(let d): return d; case .bool(let b): return b }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        let s = try c.decode(String.self); self = .string(s)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .int(let i): try c.encode(i); case .double(let d): try c.encode(d); case .bool(let b): try c.encode(b); case .string(let s): try c.encode(s) }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.content)
                .padding(12)
                .background(message.role == .user ? SAIFColors.primary : SAIFColors.surface)
                .foregroundStyle(message.role == .user ? .white : SAIFColors.text)
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
            if message.role == .assistant { Spacer() }
        }
    }
}

struct QuickQuestionButton: View {
    let title: String
    let onTap: (String) -> Void
    init(_ title: String, onTap: @escaping (String) -> Void) { self.title = title; self.onTap = onTap }
    var body: some View {
        Button(title) { onTap(title) }
            .buttonStyle(.bordered)
    }
}
