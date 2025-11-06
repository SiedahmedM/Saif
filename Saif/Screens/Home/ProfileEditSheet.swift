import SwiftUI

struct ProfileEditSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var fullName: String = ""
    @State private var selectedGoal: Goal = .bulk
    @State private var selectedLevel: FitnessLevel = .beginner
    @State private var selectedFrequency: Int = 3
    @State private var selectedGymType: GymType = .commercial
    @State private var injuriesText: String = ""
    @State private var selectedInjuryTags: Set<String> = [] // e.g., "Shoulder", "Lower Back"
    private let commonInjuries: [String] = ["Shoulder", "Lower Back", "Knee", "Elbow", "Wrist"]
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                SAIFColors.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                        
                        // Name
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Name")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            TextField("Full Name", text: $fullName)
                                .textFieldStyle(.plain)
                                .padding(SAIFSpacing.md)
                                .background(SAIFColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                        }
                        
                        // Goal
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Primary Goal")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            
                            ForEach([Goal.bulk, Goal.cut, Goal.maintain], id: \.self) { goal in
                                SelectionButton(
                                    title: goal.displayName,
                                    isSelected: selectedGoal == goal
                                ) {
                                    selectedGoal = goal
                                }
                            }
                        }
                        
                        // Experience Level
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Experience Level")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            
                            ForEach([FitnessLevel.beginner, FitnessLevel.intermediate, FitnessLevel.advanced], id: \.self) { level in
                                SelectionButton(
                                    title: level.displayName,
                                    isSelected: selectedLevel == level
                                ) {
                                    selectedLevel = level
                                }
                            }
                        }
                        
                        // Frequency
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Workout Frequency")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            
                            HStack(spacing: SAIFSpacing.sm) {
                                ForEach(2...6, id: \.self) { freq in
                                    FrequencyButton(
                                        number: freq,
                                        isSelected: selectedFrequency == freq
                                    ) {
                                        selectedFrequency = freq
                                    }
                                }
                            }
                            
                            Text("\(selectedFrequency)x per week")
                                .font(.system(size: 12))
                                .foregroundStyle(SAIFColors.mutedText)
                        }
                        
                        // Gym Type
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Available Equipment")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            
                            ForEach([GymType.commercial, GymType.home, GymType.minimal], id: \.self) { type in
                                SelectionButton(
                                    title: type.displayName,
                                    isSelected: selectedGymType == type
                                ) {
                                    selectedGymType = type
                                }
                            }
                        }

                        // Injuries / Limitations
                        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                            Text("Injuries / Limitations")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.mutedText)
                            // Quick-select chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: SAIFSpacing.sm) {
                                    ForEach(commonInjuries, id: \.self) { tag in
                                        InjuryChip(title: tag, isSelected: selectedInjuryTags.contains(tag)) {
                                            if selectedInjuryTags.contains(tag) { selectedInjuryTags.remove(tag) } else { selectedInjuryTags.insert(tag) }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, SAIFSpacing.sm)

                            TextEditor(text: $injuriesText)
                                .frame(height: 100)
                                .padding(SAIFSpacing.md)
                                .background(SAIFColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(SAIFColors.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                                .foregroundStyle(SAIFColors.text)

                            Text("Examples: shoulder pain, lower back, knee (comma-separated or new lines)")
                                .font(.system(size: 12))
                                .foregroundStyle(SAIFColors.mutedText)
                        }
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .padding(SAIFSpacing.md)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                        }
                    }
                    .padding(SAIFSpacing.xl)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveProfile() } }
                        .disabled(isSaving || fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadCurrentProfile() }
        }
    }
    
    private func loadCurrentProfile() {
        guard let profile = authManager.userProfile else { return }
        fullName = profile.fullName ?? ""
        selectedGoal = profile.primaryGoal
        selectedLevel = profile.fitnessLevel
        selectedFrequency = profile.workoutFrequency
        selectedGymType = profile.gymType
        // Map stored items to common tags and free text
        var residual: [String] = []
        for it in profile.injuriesLimitations {
            let t = it.lowercased()
            if t.contains("shoulder") { selectedInjuryTags.insert("Shoulder") }
            else if t.contains("back") || t.contains("spine") || t.contains("disc") { selectedInjuryTags.insert("Lower Back") }
            else if t.contains("knee") || t.contains("acl") || t.contains("mcl") || t.contains("meniscus") { selectedInjuryTags.insert("Knee") }
            else if t.contains("elbow") { selectedInjuryTags.insert("Elbow") }
            else if t.contains("wrist") || t.contains("carpal") { selectedInjuryTags.insert("Wrist") }
            else { residual.append(it) }
        }
        injuriesText = residual.joined(separator: ", ")
    }
    
    private func saveProfile() async {
        guard let currentProfile = authManager.userProfile else { return }
        
        isSaving = true
        errorMessage = nil
        
        let updatedProfile = UserProfile(
            id: currentProfile.id,
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullName,
            fitnessLevel: selectedLevel,
            primaryGoal: selectedGoal,
            workoutFrequency: selectedFrequency,
            gymType: selectedGymType,
            injuriesLimitations: combinedInjuries(),
            createdAt: currentProfile.createdAt,
            updatedAt: Date()
        )
        
        do {
            try await SupabaseService.shared.updateProfile(updatedProfile)
            authManager.userProfile = updatedProfile
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
        
        isSaving = false
    }

    private func combinedInjuries() -> [String] {
        let free = parseInjuries(injuriesText)
        let tags = Array(selectedInjuryTags)
        return Array(Set(tags + free))
    }
}

private func parseInjuries(_ text: String) -> [String] {
    let separators = CharacterSet(charactersIn: ",\n")
    return text
        .components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

 

private struct InjuryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, SAIFSpacing.md)
                .padding(.vertical, SAIFSpacing.sm)
                .background(isSelected ? SAIFColors.primary : SAIFColors.surface)
                .foregroundStyle(isSelected ? .white : SAIFColors.text)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : SAIFColors.border, lineWidth: 1))
        }
    }
}

// Helper components
struct SelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SAIFColors.primary)
                }
            }
            .foregroundStyle(isSelected ? SAIFColors.text : SAIFColors.mutedText)
            .padding(SAIFSpacing.md)
            .background(isSelected ? SAIFColors.primary.opacity(0.1) : SAIFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: SAIFRadius.md)
                    .stroke(isSelected ? SAIFColors.primary : SAIFColors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}

struct FrequencyButton: View {
    let number: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? .white : SAIFColors.text)
                .background(isSelected ? SAIFColors.primary : SAIFColors.surface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? SAIFColors.primary : SAIFColors.border, lineWidth: isSelected ? 2 : 1)
                )
        }
    }
}
