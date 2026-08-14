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
        switch payload {
        case let .workout(workout):
            let sanitizedType = workout.type.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...1_440).contains(workout.durationMinutes),
                  (1...100).contains(sanitizedType.count),
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

    private func sanitizedExternalID(_ externalID: String?) -> String? {
        let sanitized = externalID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(256)
            .description
        return sanitized?.isEmpty == false ? sanitized : nil
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
