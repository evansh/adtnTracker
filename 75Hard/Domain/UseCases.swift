import Foundation

struct DashboardSnapshot: Equatable, Sendable {
    let attempt: ChallengeAttempt
    let program: ProgramDefinition
    let timing: ChallengeTiming
    let evaluation: DailyEvaluation
}

struct StartChallengeUseCase: Sendable {
    let repository: any ChallengeRepository
    let program: ProgramDefinition

    func execute(startedOn: LocalDay, now: Date = .now) async throws -> ChallengeAttempt {
        guard try await repository.activeAttempt() == nil else {
            throw DomainError.activeChallengeAlreadyExists
        }
        let attempt = ChallengeAttempt(
            programID: program.id,
            programVersion: program.version,
            startedOn: startedOn,
            createdAt: now
        )
        try await repository.save(attempt)
        return attempt
    }
}

struct GetDashboardUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler
    let evaluator: RequirementEvaluator

    func execute(on day: LocalDay) async throws -> DashboardSnapshot? {
        guard let attempt = try await repository.activeAttempt() else { return nil }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let timing = try scheduler.timing(for: attempt, program: program, on: day)
        let evidence = try await repository.evidence(attemptID: attempt.id, on: day)
        let evaluation = evaluator.evaluate(
            program: program,
            evidence: evidence,
            attemptID: attempt.id,
            day: day
        )
        return DashboardSnapshot(
            attempt: attempt,
            program: program,
            timing: timing,
            evaluation: evaluation
        )
    }
}

struct RecordEvidenceUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(
        payload: EvidencePayload,
        source: EvidenceSource = .manual,
        verification: VerificationStatus = .userReported,
        externalID: String? = nil,
        occurredAt: Date = .now
    ) async throws -> EvidenceRecord {
        try validate(payload)
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(occurredAt, calendar: scheduler.calendar)
        let timing = try scheduler.timing(for: attempt, program: program, on: day)
        guard timing.phase == .active else { throw DomainError.evidenceOutsideActiveAttempt }

        let record = EvidenceRecord(
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: source,
            verification: verification,
            externalID: sanitizedExternalID(externalID),
            payload: payload
        )
        try await repository.save(record)
        return record
    }

    private func validate(_ payload: EvidencePayload) throws {
        try EvidenceValidator().validate(payload)
    }

    private func sanitizedExternalID(_ externalID: String?) -> String? {
        let sanitized = externalID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(256)
            .description
        return sanitized?.isEmpty == false ? sanitized : nil
    }
}

struct WorkoutDraft: Equatable, Sendable {
    let id: UUID?
    let slot: WorkoutSlot
    let type: String
    let startedAt: Date
    let durationMinutes: Int
    let isOutdoor: Bool
    let distanceMeters: Double?
    let notes: String?

    init(
        id: UUID? = nil,
        slot: WorkoutSlot,
        type: String,
        startedAt: Date,
        durationMinutes: Int,
        isOutdoor: Bool,
        distanceMeters: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.slot = slot
        self.type = type
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.isOutdoor = isOutdoor
        self.distanceMeters = distanceMeters
        self.notes = notes
    }
}

struct ListRecordedWorkoutsUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(on day: LocalDay) async throws -> [RecordedWorkout] {
        guard let attempt = try await repository.activeAttempt() else { return [] }
        return try await repository.evidence(attemptID: attempt.id, on: day)
            .compactMap(RecordedWorkout.init)
            .sorted { lhs, rhs in
                let lhsSlot = lhs.workout.assignedSlot == .first ? 0 : 1
                let rhsSlot = rhs.workout.assignedSlot == .first ? 0 : 1
                return lhsSlot == rhsSlot ? lhs.occurredAt < rhs.occurredAt : lhsSlot < rhsSlot
            }
    }
}

struct SaveManualWorkoutUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(_ draft: WorkoutDraft) async throws -> RecordedWorkout {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }

        let workout = try normalizedWorkout(from: draft)
        let day = LocalDay(draft.startedAt, calendar: scheduler.calendar)
        let timing = try scheduler.timing(for: attempt, program: program, on: day)
        guard timing.phase == .active else { throw DomainError.evidenceOutsideActiveAttempt }

        let existing = try await existingRecord(id: draft.id, attemptID: attempt.id)
        let dailyEvidence = try await repository.evidence(attemptID: attempt.id, on: day)
        let hasSlotConflict = dailyEvidence.contains { record in
            guard record.id != existing?.id,
                  case let .workout(candidate) = record.payload
            else { return false }
            return candidate.assignedSlot == draft.slot
        }
        guard !hasSlotConflict else { throw DomainError.workoutSlotAlreadyAssigned }

        let record = EvidenceRecord(
            id: existing?.id ?? UUID(),
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: draft.startedAt,
            source: .manual,
            verification: .userReported,
            payload: .workout(workout)
        )
        try await repository.save(record)
        guard let recorded = RecordedWorkout(record: record) else {
            throw DomainError.persistenceFailure
        }
        return recorded
    }

    private func existingRecord(id: UUID?, attemptID: UUID) async throws -> EvidenceRecord? {
        guard let id else { return nil }
        guard let record = try await repository.evidence(id: id),
              record.attemptID == attemptID,
              case .workout = record.payload
        else { throw DomainError.evidenceNotFound }
        guard record.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
        return record
    }

    private func normalizedWorkout(from draft: WorkoutDraft) throws -> WorkoutEvidence {
        let type = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes?.isEmpty == false ? notes : nil
        let workout = WorkoutEvidence(
            type: type,
            durationMinutes: draft.durationMinutes,
            isOutdoor: draft.isOutdoor,
            distanceMeters: draft.distanceMeters,
            assignedSlot: draft.slot,
            notes: normalizedNotes
        )
        try EvidenceValidator().validate(.workout(workout))
        return workout
    }
}

struct DeleteManualWorkoutUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(id: UUID) async throws {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let record = try await repository.evidence(id: id),
              record.attemptID == attempt.id,
              case .workout = record.payload
        else { throw DomainError.evidenceNotFound }
        guard record.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
        try await repository.deleteEvidence(id: id)
    }
}

private struct EvidenceValidator {
    func validate(_ payload: EvidencePayload) throws {
        switch payload {
        case let .workout(workout):
            let sanitizedType = workout.type.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteCount = workout.notes?.count ?? 0
            guard (1...1_440).contains(workout.durationMinutes),
                  (1...100).contains(sanitizedType.count),
                  noteCount <= 500,
                  workout.distanceMeters.map({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }) ?? true
            else { throw DomainError.invalidEvidenceValue }
        case let .hydration(milliliters):
            guard (1...5_000).contains(milliliters) else { throw DomainError.invalidEvidenceValue }
        case let .reading(reading):
            guard reading.startingPage >= 0,
                  reading.endingPage > reading.startingPage,
                  reading.pagesRead <= 1_000
            else { throw DomainError.invalidEvidenceValue }
        case .diet, .progressPhoto:
            break
        }
    }
}

struct RestartChallengeUseCase: Sendable {
    let repository: any ChallengeRepository
    let program: ProgramDefinition
    let evaluator: RequirementEvaluator

    func execute(
        failedOn: LocalDay,
        restartOn: LocalDay,
        now: Date = .now
    ) async throws -> ChallengeAttempt {
        guard restartOn > failedOn else { throw DomainError.invalidRestartDate }
        guard var existing = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        let evidence = try await repository.evidence(attemptID: existing.id, on: failedOn)
        let daily = evaluator.evaluate(
            program: program,
            evidence: evidence,
            attemptID: existing.id,
            day: failedOn
        )
        existing.status = .failed(
            failedOn: failedOn,
            unmetRequirementIDs: daily.requirements.filter { !$0.status.isSatisfied }.map(\.id)
        )
        try await repository.save(existing)

        let replacement = ChallengeAttempt(
            programID: program.id,
            programVersion: program.version,
            startedOn: restartOn,
            createdAt: now
        )
        try await repository.save(replacement)
        return replacement
    }
}
