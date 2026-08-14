import Foundation

struct ChallengeTiming: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case upcoming, active, ended }

    let phase: Phase
    let dayNumber: Int?
    let completionDate: LocalDay
    let daysRemaining: Int
    let completionPercentage: Double
}

struct ChallengeScheduler: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func timing(
        for attempt: ChallengeAttempt,
        program: ProgramDefinition,
        on day: LocalDay
    ) throws -> ChallengeTiming {
        guard program.durationDays > 0 else { throw DomainError.invalidProgramDefinition }
        let startDate = try attempt.startedOn.date(in: calendar)
        let queryDate = try day.date(in: calendar)
        guard let completionDate = calendar.date(
            byAdding: .day,
            value: program.durationDays - 1,
            to: startDate
        ) else {
            throw DomainError.invalidLocalDay
        }

        let offset = calendar.dateComponents([.day], from: startDate, to: queryDate).day ?? 0
        let completionDay = LocalDay(completionDate, calendar: calendar)

        if offset < 0 {
            return ChallengeTiming(
                phase: .upcoming,
                dayNumber: nil,
                completionDate: completionDay,
                daysRemaining: program.durationDays,
                completionPercentage: 0
            )
        }

        guard offset < program.durationDays else {
            return ChallengeTiming(
                phase: .ended,
                dayNumber: nil,
                completionDate: completionDay,
                daysRemaining: 0,
                completionPercentage: 100
            )
        }

        let dayNumber = offset + 1
        return ChallengeTiming(
            phase: .active,
            dayNumber: dayNumber,
            completionDate: completionDay,
            daysRemaining: program.durationDays - dayNumber,
            completionPercentage: Double(dayNumber) / Double(program.durationDays) * 100
        )
    }
}
