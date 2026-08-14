import XCTest
@testable import Hard75

final class ChallengeSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    func testDayCalculationSurvivesDaylightSavingBoundary() throws {
        let attempt = ChallengeAttempt(
            programID: ProgramDefinition.seventyFiveHard.id,
            programVersion: 1,
            startedOn: LocalDay(year: 2026, month: 3, day: 7)
        )
        let timing = try ChallengeScheduler(calendar: calendar).timing(
            for: attempt,
            program: .seventyFiveHard,
            on: LocalDay(year: 2026, month: 3, day: 9)
        )

        XCTAssertEqual(timing.phase, .active)
        XCTAssertEqual(timing.dayNumber, 3)
        XCTAssertEqual(timing.daysRemaining, 72)
    }

    func testStartAndCompletionDatesAreInclusive() throws {
        let attempt = ChallengeAttempt(
            programID: ProgramDefinition.seventyFiveHard.id,
            programVersion: 1,
            startedOn: LocalDay(year: 2026, month: 12, day: 1)
        )
        let scheduler = ChallengeScheduler(calendar: calendar)

        let first = try scheduler.timing(
            for: attempt,
            program: .seventyFiveHard,
            on: LocalDay(year: 2026, month: 12, day: 1)
        )
        let final = try scheduler.timing(
            for: attempt,
            program: .seventyFiveHard,
            on: LocalDay(year: 2027, month: 2, day: 13)
        )
        let after = try scheduler.timing(
            for: attempt,
            program: .seventyFiveHard,
            on: LocalDay(year: 2027, month: 2, day: 14)
        )

        XCTAssertEqual(first.dayNumber, 1)
        XCTAssertEqual(first.completionDate, LocalDay(year: 2027, month: 2, day: 13))
        XCTAssertEqual(final.dayNumber, 75)
        XCTAssertEqual(final.daysRemaining, 0)
        XCTAssertEqual(after.phase, .ended)
    }

    func testFutureStartIsUpcoming() throws {
        let attempt = ChallengeAttempt(
            programID: ProgramDefinition.seventyFiveHard.id,
            programVersion: 1,
            startedOn: LocalDay(year: 2027, month: 1, day: 1)
        )
        let timing = try ChallengeScheduler(calendar: calendar).timing(
            for: attempt,
            program: .seventyFiveHard,
            on: LocalDay(year: 2026, month: 12, day: 31)
        )

        XCTAssertEqual(timing.phase, .upcoming)
        XCTAssertNil(timing.dayNumber)
        XCTAssertEqual(timing.completionPercentage, 0)
    }

    func testInvalidCalendarDayIsRejectedRatherThanNormalized() {
        XCTAssertThrowsError(try LocalDay(year: 2026, month: 2, day: 31).date(in: calendar)) { error in
            XCTAssertEqual(error as? DomainError, .invalidLocalDay)
        }
    }
}
