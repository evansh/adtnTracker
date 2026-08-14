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

    func testManualWorkoutCanBeCreatedEditedAndDeleted() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        _ = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day)
        let startedAt = try day.date(in: calendar).addingTimeInterval(8 * 60 * 60)
        let save = SaveManualWorkoutUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )

        let created = try await save.execute(WorkoutDraft(
            slot: .first,
            type: "  Outdoor Walk  ",
            startedAt: startedAt,
            durationMinutes: 45,
            isOutdoor: true,
            distanceMeters: 5_000,
            notes: "  Morning session  "
        ))
        XCTAssertEqual(created.workout.type, "Outdoor Walk")
        XCTAssertEqual(created.workout.notes, "Morning session")

        let edited = try await save.execute(WorkoutDraft(
            id: created.id,
            slot: .second,
            type: "Strength",
            startedAt: startedAt,
            durationMinutes: 50,
            isOutdoor: false
        ))
        XCTAssertEqual(edited.id, created.id)
        XCTAssertEqual(edited.workout.assignedSlot, .second)

        let listed = try await ListRecordedWorkoutsUseCase(repository: repository).execute(on: day)
        XCTAssertEqual(listed, [edited])

        try await DeleteManualWorkoutUseCase(repository: repository).execute(id: edited.id)
        let afterDelete = try await ListRecordedWorkoutsUseCase(repository: repository).execute(on: day)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testManualWorkoutRejectsDuplicateDailySlot() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        _ = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day)
        let startedAt = try day.date(in: calendar).addingTimeInterval(8 * 60 * 60)
        let save = SaveManualWorkoutUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )
        _ = try await save.execute(WorkoutDraft(
            slot: .first,
            type: "Walk",
            startedAt: startedAt,
            durationMinutes: 45,
            isOutdoor: true
        ))

        do {
            _ = try await save.execute(WorkoutDraft(
                slot: .first,
                type: "Run",
                startedAt: startedAt.addingTimeInterval(60 * 60),
                durationMinutes: 45,
                isOutdoor: true
            ))
            XCTFail("Expected the duplicate slot to be rejected")
        } catch {
            XCTAssertEqual(error as? DomainError, .workoutSlotAlreadyAssigned)
        }
    }

    func testImportedWorkoutCannotBeDeletedByManualUseCase() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day)
        let imported = EvidenceRecord(
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: try day.date(in: calendar),
            source: .appleHealth,
            verification: .sourceVerified,
            externalID: "workout-123",
            payload: .workout(WorkoutEvidence(
                type: "Run",
                durationMinutes: 45,
                isOutdoor: true,
                distanceMeters: 7_000,
                assignedSlot: .first
            ))
        )
        try await repository.save(imported)

        do {
            try await DeleteManualWorkoutUseCase(repository: repository).execute(id: imported.id)
            XCTFail("Expected imported evidence to be protected")
        } catch {
            XCTAssertEqual(error as? DomainError, .cannotModifyImportedEvidence)
        }
    }

    func testManualRequirementCanBeCheckedAndCorrected() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day)
        let occurredAt = try day.date(in: calendar).addingTimeInterval(12 * 60 * 60)
        let useCase = SetManualRequirementCompletionUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )

        try await useCase.execute(
            requirementID: "progress-photo",
            isComplete: true,
            occurredAt: occurredAt
        )
        var evidence = try await repository.evidence(attemptID: attempt.id, on: day)
        XCTAssertEqual(evidence.count, 1)

        try await useCase.execute(
            requirementID: "progress-photo",
            isComplete: false,
            occurredAt: occurredAt
        )
        evidence = try await repository.evidence(attemptID: attempt.id, on: day)
        XCTAssertTrue(evidence.isEmpty)
    }

    func testDashboardUsesChallengeCreationTimezoneAfterTravel() async throws {
        let repository = InMemoryChallengeRepository()
        let attempt = ChallengeAttempt(
            programID: ProgramDefinition.seventyFiveHard.id,
            programVersion: ProgramDefinition.seventyFiveHard.version,
            startedOn: LocalDay(year: 2026, month: 8, day: 14),
            timeZoneIdentifier: "America/Chicago"
        )
        try await repository.save(attempt)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter().date(from: "2026-08-15T04:30:00Z")!

        let snapshot = try await GetDashboardUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: utcCalendar),
            evaluator: RequirementEvaluator()
        ).execute(at: date)

        XCTAssertEqual(snapshot?.day, LocalDay(year: 2026, month: 8, day: 14))
        XCTAssertEqual(snapshot?.timing.dayNumber, 1)
    }

    func testHydrationEntryCanBeCorrectedAndDeleted() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(
            startedOn: day,
            timeZoneIdentifier: "UTC"
        )
        let occurredAt = try day.date(in: calendar).addingTimeInterval(12 * 60 * 60)
        let save = SaveManualHydrationUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )

        let created = try await save.execute(milliliters: 473, occurredAt: occurredAt)
        let corrected = try await save.execute(
            id: created.id,
            milliliters: 355,
            occurredAt: occurredAt
        )
        var entries = try await ListHydrationUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)
        XCTAssertEqual(entries, [corrected])

        try await DeleteManualHydrationUseCase(repository: repository).execute(id: corrected.id)
        entries = try await ListHydrationUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)
        XCTAssertTrue(entries.isEmpty)
    }

    func testDietPlanAndComplianceRemainUserCorrectable() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day, timeZoneIdentifier: "UTC")
        let plan = try await ConfigureDietPlanUseCase(repository: repository).execute(
            name: "  Whole Foods  ",
            rules: "  No alcohol or added sugar.  "
        )
        XCTAssertEqual(plan.name, "Whole Foods")

        let occurredAt = try day.date(in: calendar).addingTimeInterval(20 * 60 * 60)
        let setCompliance = SetDietComplianceUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )
        _ = try await setCompliance.execute(
            isCompliant: false,
            notes: "Tapped incorrectly",
            occurredAt: occurredAt
        )
        let corrected = try await setCompliance.execute(
            isCompliant: true,
            notes: "Corrected",
            occurredAt: occurredAt
        )
        let saved = try await GetDietComplianceUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)

        XCTAssertEqual(saved, corrected)
        XCTAssertTrue(saved?.isCompliant == true)
        XCTAssertEqual(saved?.notes, "Corrected")
        let dietEvidence = try await repository.evidence(attemptID: attempt.id, on: day)
        XCTAssertEqual(dietEvidence.count, 1)
    }

    func testReadingEntryCanBeCorrectedAndDeleted() async throws {
        let repository = InMemoryChallengeRepository()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day, timeZoneIdentifier: "UTC")
        let occurredAt = try day.date(in: calendar).addingTimeInterval(18 * 60 * 60)
        let save = SaveManualReadingUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )

        let created = try await save.execute(
            bookTitle: "  Atomic Habits  ",
            startingPage: 10,
            endingPage: 20,
            occurredAt: occurredAt
        )
        let corrected = try await save.execute(
            id: created.id,
            bookID: created.reading.bookID,
            bookTitle: "Atomic Habits",
            startingPage: 10,
            endingPage: 22,
            occurredAt: occurredAt
        )
        var readings = try await ListReadingUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)
        XCTAssertEqual(readings, [corrected])
        XCTAssertEqual(corrected.reading.pagesRead, 12)

        try await DeleteManualReadingUseCase(repository: repository).execute(id: corrected.id)
        readings = try await ListReadingUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)
        XCTAssertTrue(readings.isEmpty)
    }

    func testProgressPhotoIsStoredPrivatelyAndCanBeReplacedAndDeleted() async throws {
        let repository = InMemoryChallengeRepository()
        let photoStore = InMemoryProgressPhotoStore()
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: day, timeZoneIdentifier: "UTC")
        let occurredAt = try day.date(in: calendar).addingTimeInterval(9 * 60 * 60)
        let save = SaveProgressPhotoUseCase(
            repository: repository,
            photoStore: photoStore,
            catalog: DefaultProgramCatalog(),
            scheduler: ChallengeScheduler(calendar: calendar)
        )

        let created = try await save.execute(jpegData: Data([1, 2, 3]), occurredAt: occurredAt)
        let replaced = try await save.execute(jpegData: Data([4, 5, 6]), occurredAt: occurredAt)
        XCTAssertEqual(replaced.id, created.id)
        XCTAssertEqual(replaced.photoRecordID, created.photoRecordID)
        let replacedData = try await photoStore.jpegData(id: replaced.photoRecordID)
        let storedPhoto = try await GetProgressPhotoUseCase(repository: repository)
            .execute(attemptID: attempt.id, on: day)
        XCTAssertEqual(replacedData, Data([4, 5, 6]))
        XCTAssertEqual(storedPhoto, replaced)

        try await DeleteProgressPhotoUseCase(
            repository: repository,
            photoStore: photoStore
        ).execute(id: replaced.id)
        let deletedData = try await photoStore.jpegData(id: replaced.photoRecordID)
        let deletedEvidence = try await repository.evidence(id: replaced.id)
        XCTAssertNil(deletedData)
        XCTAssertNil(deletedEvidence)
    }

    func testIncompleteDayCanBeCorrectedInsteadOfForcingFailure() async throws {
        let repository = InMemoryChallengeRepository()
        let startDay = LocalDay(year: 2026, month: 8, day: 14)
        _ = try await StartChallengeUseCase(
            repository: repository,
            program: .seventyFiveHard
        ).execute(startedOn: startDay, timeZoneIdentifier: "UTC")
        let scheduler = ChallengeScheduler(calendar: calendar)
        let finder = FindFirstIncompleteDayUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: scheduler,
            evaluator: RequirementEvaluator()
        )
        let nextDay = try startDay.date(in: calendar).addingTimeInterval(36 * 60 * 60)

        let initialReview = try await finder.execute(at: nextDay)
        XCTAssertEqual(initialReview?.day, startDay)
        XCTAssertEqual(initialReview?.unmetRequirements.count, 7)

        let completion = SetManualRequirementCompletionUseCase(
            repository: repository,
            catalog: DefaultProgramCatalog(),
            scheduler: scheduler
        )
        let correctionTime = try startDay.date(in: calendar).addingTimeInterval(12 * 60 * 60)
        for requirement in ProgramDefinition.seventyFiveHard.requirements {
            try await completion.execute(
                requirementID: requirement.id,
                isComplete: true,
                occurredAt: correctionTime
            )
        }

        let correctedReview = try await finder.execute(at: nextDay)
        let activeAttempt = try await repository.activeAttempt()
        XCTAssertNil(correctedReview)
        XCTAssertNotNil(activeAttempt)
    }
}
