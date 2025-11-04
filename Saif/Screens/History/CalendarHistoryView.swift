import SwiftUI

struct CalendarHistoryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var authManager: AuthManager

    @State private var month: Date = Date()
    @State private var selected: Date? = nil

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            VStack(spacing: SAIFSpacing.lg) {
                header
                calendarGrid
                if let sel = selected { DayHistoryView(date: sel).environmentObject(workoutManager) }
                Spacer()
            }
            .padding(SAIFSpacing.xl)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await workoutManager.loadSessionsForMonth(containing: month) } }
    }

    private var header: some View {
        HStack {
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month, format: .dateTime.year().month())
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var calendarGrid: some View {
        let days = makeDays()
        return VStack(spacing: 8) {
            HStack { ForEach(["S","M","T","W","T","F","S"], id: \.self) { Text($0).foregroundStyle(SAIFColors.mutedText).frame(maxWidth: .infinity) } }
            ForEach(0..<rows(for: days), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row*7+col
                        if idx < days.count { dayCell(days[idx]) } else { Spacer() }
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date?) -> some View {
        Group {
            if let d = date {
                let has = !workoutManager.sessions(on: d).isEmpty
                Button { selected = d } label: {
                    VStack(spacing: 4) {
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SAIFColors.text)
                        Circle()
                            .fill(has ? SAIFColors.primary : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedDayMatch(d) ? SAIFColors.primary.opacity(0.1) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }
        }
    }

    private func selectedDayMatch(_ date: Date) -> Bool {
        guard let s = selected else { return false }
        return Calendar.current.isDate(s, inSameDayAs: date)
    }

    private func rows(for days: [Date?]) -> Int { Int(ceil(Double(days.count)/7.0)) }

    private func makeDays() -> [Date?] {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let weekday = cal.component(.weekday, from: startOfMonth)
        let offset = weekday - cal.firstWeekday
        var result: [Date?] = Array(repeating: nil, count: (offset+7)%7)
        let range = cal.range(of: .day, in: .month, for: startOfMonth)!
        for day in range {
            result.append(cal.date(byAdding: .day, value: day-1, to: startOfMonth))
        }
        return result
    }

    private func changeMonth(_ delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = newMonth
            selected = nil
            Task { await workoutManager.loadSessionsForMonth(containing: month) }
        }
    }
}

struct DayHistoryView: View {
    let date: Date
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var setsBySession: [UUID: [ExerciseSet]] = [:]
    @State private var exercisesById: [UUID: Exercise] = [:]
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
            Text(date, format: .dateTime.year().month().day())
                .font(.system(size: 18, weight: .semibold))
            let sessions = workoutManager.sessions(on: date)
            if sessions.isEmpty { Text("No workouts").foregroundStyle(SAIFColors.mutedText) }
            ForEach(sessions, id: \.id) { s in
                CardView(title: s.workoutType.capitalized) {
                    if let sets = setsBySession[s.id] {
                        let groups = groupCounts(for: sets)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(groups.keys.sorted(), id: \.self) { g in
                                HStack { Text(g.capitalized); Spacer(); Text("\(groups[g] ?? 0) sets").foregroundStyle(SAIFColors.mutedText) }
                            }
                        }
                    } else if loading {
                        ProgressView()
                    } else {
                        Text("Tap to load details").foregroundStyle(SAIFColors.mutedText)
                    }
                }
                .onTapGesture { loadSets(for: s) }
            }
        }
    }

    private func loadSets(for session: WorkoutSession) {
        loading = true
        Task {
            let sets = (try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: session.id)) ?? []
            setsBySession[session.id] = sets
            let exIds = Array(Set(sets.map { $0.exerciseId }))
            let exercises = (try? await SupabaseService.shared.getExercisesByIds(exIds)) ?? []
            var map: [UUID: Exercise] = [:]
            exercises.forEach { map[$0.id] = $0 }
            exercisesById.merge(map) { _, new in new }
            loading = false
        }
    }

    private func groupCounts(for sets: [ExerciseSet]) -> [String:Int] {
        var counts: [String:Int] = [:]
        for set in sets {
            let group = exercisesById[set.exerciseId]?.muscleGroup ?? "unknown"
            counts[group, default: 0] += 1
        }
        return counts
    }
}

#Preview { NavigationStack { CalendarHistoryView().environmentObject(WorkoutManager()).environmentObject(AuthManager()) } }
