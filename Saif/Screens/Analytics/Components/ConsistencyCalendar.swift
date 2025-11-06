import SwiftUI

struct ConsistencyCalendar: View {
    let workoutDates: [Date]
    
    private var weeks: [[Date?]] {
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = []
        for dayOffset in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            currentWeek.append(date)
            if currentWeek.count == 7 { weeks.append(currentWeek); currentWeek = [] }
        }
        if !currentWeek.isEmpty { weeks.append(currentWeek) }
        return weeks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SAIFColors.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 4) {
                ForEach(weeks.indices, id: \.self) { w in
                    HStack(spacing: 4) {
                        ForEach(0..<7) { d in
                            if d < weeks[w].count, let date = weeks[w][d] {
                                CalendarDay(date: date, hasWorkout: workoutDates.contains { Calendar.current.isDate($0, inSameDayAs: date) })
                            } else {
                                Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CalendarDay: View {
    let date: Date
    let hasWorkout: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(hasWorkout ? .green : SAIFColors.border)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 8, weight: hasWorkout ? .bold : .regular))
                    .foregroundStyle(hasWorkout ? .white : SAIFColors.mutedText)
            )
    }
}

