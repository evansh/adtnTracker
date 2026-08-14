import XCTest
@testable import Hard75

final class UseCaseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCannotStartSecondActiveChallenge() async throws {
        let repository = InMemoryChallengeRepository()
        let useCase = StartChallengeUseCase(repository: repository, program: .seventyFiveHard)
        let day = LocalDay(year: 2026, month: 8, day: 14)

        _ = try await useCase.execute(startedOn: day)

        do {
            _ = try await useCase.execute(startedOn: day)
            XCTFail("Expected an active challenge error")
        } catch {
            XCTAssertEqual(error as? DomainError, .activeChallengeAlreadyExists)
        }
    }

    func testEvidenceValidationRejectsUnsafeValues() async throws {
        let repository = InMemoryChallengeRepository()
        let start = StartChallengeUseCase(repository: repository, program: .seventyFiveHard)
        _ = try await start.execute(startedOn: LocalDay(year: 2026, month: 8, day: 14))
        let recorder = RecordEvidenceUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )
        let occurredAt = try LocalDay(year: 2026, month: 8, day: 14).date(in: calendar)

        do {
            _ = try await recorder.execute(
                payload: .hydration(milliliters: -1),
                occurredAt: occurredAt
            )
            XCTFail("Expected validation to fail")
        } catch {
            XCTAssertEqual(error as? DomainError, .invalidEvidenceValue)
        }
    }

    func testRestartPreservesFailedAttemptAndEvidence() async throws {
        let repository = InMemoryChallengeRepository()
        let failedOn = LocalDay(year: 2026, month: 8, day: 14)
        let original = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: failedOn)
        try await repository.save(EvidenceRecord(
            attemptID: original.id,
            occurredOn: failedOn,
            occurredAt: .now,
            source: .manual,
            verification: .userReported,
            payload: .diet(isCompliant: true)
        ))

        let replacement = try await RestartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard,
            evaluator: RequirementEvaluator()
        ).execute(
            failedOn: failedOn,
            restartOn: LocalDay(year: 2026, month: 8, day: 15)
        )

        let attempts = try await repository.allAttempts()
        let activeAttempt = try await repository.activeAttempt()
        let originalEvidence = try await repository.evidence(attemptID: original.id, on: failedOn)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(activeAttempt?.id, replacement.id)
        guard case let .failed(day, unmet) = attempts[0].status else {
            return XCTFail("The original attempt should be retained as failed")
        }
        XCTAssertEqual(day, failedOn)
        XCTAssertTrue(unmet.contains("water"))
        XCTAssertFalse(unmet.contains("diet"))
        XCTAssertEqual(originalEvidence.count, 1)
    }

    func testRestartDateMustFollowFailureDate() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        _ = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day)

        do {
            _ = try await RestartChallengeUseCase(
                repository: repository,
                program: .seventyFiveHard,
                evaluator: RequirementEvaluator()
            ).execute(failedOn: day, restartOn: day)
            XCTFail("Expected invalid restart date")
        } catch {
            XCTAssertEqual(error as? DomainError, .invalidRestartDate)
        }
    }
}
