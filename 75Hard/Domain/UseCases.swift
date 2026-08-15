import Foundation

struct DashboardSnapshot: Equatable, Sendable {
    let attempt: ChallengeAttempt
    let program: ProgramDefinition
    let day: LocalDay
    let timing: ChallengeTiming
    let evaluation: DailyEvaluation
}

struct IncompleteDayReview: Equatable, Sendable {
    let attempt: ChallengeAttempt
    let day: LocalDay
    let dayNumber: Int
    let unmetRequirements: [RequirementEvaluation]
}

struct StartChallengeUseCase: Sendable {
    let repository: any ChallengeRepository
    let program: ProgramDefinition

    func execute(
        startedOn: LocalDay,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        now: Date = .now
    ) async throws -> ChallengeAttempt {
        guard try await repository.activeAttempt() == nil else {
            throw DomainError.activeChallengeAlreadyExists
        }
        let attempt = ChallengeAttempt(
            programID: program.id,
            programVersion: program.version,
            startedOn: startedOn,
            timeZoneIdentifier: timeZoneIdentifier,
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

    func execute(at date: Date = .now) async throws -> DashboardSnapshot? {
        guard let attempt = try await repository.activeAttempt() else { return nil }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(date, calendar: scheduler.calendar(for: attempt))
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
            day: day,
            timing: timing,
            evaluation: evaluation
        )
    }
}

struct FindFirstIncompleteDayUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler
    let evaluator: RequirementEvaluator

    func execute(at date: Date = .now) async throws -> IncompleteDayReview? {
        guard let attempt = try await repository.activeAttempt() else { return nil }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let calendar = scheduler.calendar(for: attempt)
        let today = LocalDay(date, calendar: calendar)
        let todayTiming = try scheduler.timing(for: attempt, program: program, on: today)
        let elapsedDays: Int
        switch todayTiming.phase {
        case .upcoming:
            return nil
        case .active:
            elapsedDays = max(0, (todayTiming.dayNumber ?? 1) - 1)
        case .ended:
            elapsedDays = program.durationDays
        }

        let startDate = try attempt.startedOn.date(in: calendar)
        for offset in 0..<elapsedDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                throw DomainError.invalidLocalDay
            }
            let day = LocalDay(date, calendar: calendar)
            let evidence = try await repository.evidence(attemptID: attempt.id, on: day)
            let evaluation = evaluator.evaluate(
                program: program,
                evidence: evidence,
                attemptID: attempt.id,
                day: day
            )
            let unmet = evaluation.requirements.filter { !$0.status.isSatisfied }
            if !unmet.isEmpty {
                return IncompleteDayReview(
                    attempt: attempt,
                    day: day,
                    dayNumber: offset + 1,
                    unmetRequirements: unmet
                )
            }
        }
        return nil
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
        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
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

struct SetManualRequirementCompletionUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(
        requirementID: String,
        isComplete: Bool,
        notes: String? = nil,
        occurredAt: Date = .now
    ) async throws {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion),
              program.requirements.contains(where: { $0.id == requirementID })
        else { throw DomainError.invalidProgramDefinition }

        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
        let timing = try scheduler.timing(for: attempt, program: program, on: day)
        guard timing.phase == .active else { throw DomainError.evidenceOutsideActiveAttempt }

        let dailyEvidence = try await repository.evidence(attemptID: attempt.id, on: day)
        let existing = dailyEvidence.first { record in
            guard case let .manualCompletion(completion) = record.payload else { return false }
            return completion.requirementID == requirementID
        }

        guard isComplete else {
            if let existing { try await repository.deleteEvidence(id: existing.id) }
            return
        }

        let normalizedNotes = notes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(500)
            .description
        let payload = EvidencePayload.manualCompletion(ManualCompletionEvidence(
            requirementID: requirementID,
            notes: normalizedNotes?.isEmpty == false ? normalizedNotes : nil
        ))
        try EvidenceValidator().validate(payload)
        try await repository.save(EvidenceRecord(
            id: existing?.id ?? UUID(),
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: .manual,
            verification: .userReported,
            payload: payload
        ))
    }
}

struct ListHydrationUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(attemptID: UUID, on day: LocalDay) async throws -> [RecordedHydration] {
        try await repository.evidence(attemptID: attemptID, on: day)
            .compactMap(RecordedHydration.init)
            .sorted { $0.occurredAt < $1.occurredAt }
    }
}

struct SaveManualHydrationUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(
        id: UUID? = nil,
        milliliters: Int,
        occurredAt: Date = .now
    ) async throws -> RecordedHydration {
        let payload = EvidencePayload.hydration(milliliters: milliliters)
        try EvidenceValidator().validate(payload)
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
        guard try scheduler.timing(for: attempt, program: program, on: day).phase == .active else {
            throw DomainError.evidenceOutsideActiveAttempt
        }

        var recordID = UUID()
        if let id {
            guard let existing = try await repository.evidence(id: id),
                  existing.attemptID == attempt.id,
                  case .hydration = existing.payload
            else { throw DomainError.evidenceNotFound }
            guard existing.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
            recordID = existing.id
        }

        let record = EvidenceRecord(
            id: recordID,
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: .manual,
            verification: .userReported,
            payload: payload
        )
        try await repository.save(record)
        guard let hydration = RecordedHydration(record: record) else {
            throw DomainError.persistenceFailure
        }
        return hydration
    }
}

struct DeleteManualHydrationUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(id: UUID) async throws {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let record = try await repository.evidence(id: id),
              record.attemptID == attempt.id,
              case .hydration = record.payload
        else { throw DomainError.evidenceNotFound }
        guard record.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
        try await repository.deleteEvidence(id: id)
    }
}

struct ConfigureDietPlanUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(name: String, rules: String) async throws -> DietPlan {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(normalizedName.count),
              (1...2_000).contains(normalizedRules.count)
        else { throw DomainError.invalidEvidenceValue }
        guard var attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        let plan = DietPlan(name: normalizedName, rules: normalizedRules)
        attempt.dietPlan = plan
        try await repository.save(attempt)
        return plan
    }
}

struct GetDietComplianceUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(attemptID: UUID, on day: LocalDay) async throws -> RecordedDietCompliance? {
        try await repository.evidence(attemptID: attemptID, on: day)
            .compactMap(RecordedDietCompliance.init)
            .max { $0.occurredAt < $1.occurredAt }
    }
}

struct SetDietComplianceUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(
        isCompliant: Bool,
        notes: String? = nil,
        occurredAt: Date = .now
    ) async throws -> RecordedDietCompliance {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard attempt.dietPlan != nil else { throw DomainError.invalidEvidenceValue }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
        guard try scheduler.timing(for: attempt, program: program, on: day).phase == .active else {
            throw DomainError.evidenceOutsideActiveAttempt
        }
        let dailyEvidence = try await repository.evidence(attemptID: attempt.id, on: day)
        let existing = dailyEvidence.first { RecordedDietCompliance(record: $0) != nil }
        for manual in dailyEvidence where isManualDietCompletion(manual) {
            try await repository.deleteEvidence(id: manual.id)
        }

        let normalizedNotes = notes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(500)
            .description
        let payload = EvidencePayload.dietCompliance(DietComplianceEvidence(
            isCompliant: isCompliant,
            notes: normalizedNotes?.isEmpty == false ? normalizedNotes : nil
        ))
        try EvidenceValidator().validate(payload)
        let record = EvidenceRecord(
            id: existing?.id ?? UUID(),
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: .manual,
            verification: .userReported,
            payload: payload
        )
        try await repository.save(record)
        guard let compliance = RecordedDietCompliance(record: record) else {
            throw DomainError.persistenceFailure
        }
        return compliance
    }

    private func isManualDietCompletion(_ record: EvidenceRecord) -> Bool {
        guard case let .manualCompletion(completion) = record.payload else { return false }
        return completion.requirementID == "diet"
    }
}

struct ListReadingUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(attemptID: UUID, on day: LocalDay) async throws -> [RecordedReading] {
        try await repository.evidence(attemptID: attemptID, on: day)
            .compactMap(RecordedReading.init)
            .sorted { $0.occurredAt < $1.occurredAt }
    }
}

struct SaveManualReadingUseCase: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(
        id: UUID? = nil,
        bookID: UUID? = nil,
        bookTitle: String,
        startingPage: Int,
        endingPage: Int,
        occurredAt: Date = .now
    ) async throws -> RecordedReading {
        let normalizedTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(normalizedTitle.count) else {
            throw DomainError.invalidEvidenceValue
        }
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
        guard try scheduler.timing(for: attempt, program: program, on: day).phase == .active else {
            throw DomainError.evidenceOutsideActiveAttempt
        }

        var recordID = UUID()
        var resolvedBookID = bookID ?? UUID()
        if let id {
            guard let existing = try await repository.evidence(id: id),
                  existing.attemptID == attempt.id,
                  case let .reading(existingReading) = existing.payload
            else { throw DomainError.evidenceNotFound }
            guard existing.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
            recordID = existing.id
            resolvedBookID = existingReading.bookID
        }

        let payload = EvidencePayload.reading(ReadingEvidence(
            bookID: resolvedBookID,
            startingPage: startingPage,
            endingPage: endingPage,
            bookTitle: normalizedTitle
        ))
        try EvidenceValidator().validate(payload)
        let record = EvidenceRecord(
            id: recordID,
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: .manual,
            verification: .userReported,
            payload: payload
        )
        try await repository.save(record)
        guard let reading = RecordedReading(record: record) else {
            throw DomainError.persistenceFailure
        }
        return reading
    }
}

struct DeleteManualReadingUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(id: UUID) async throws {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let record = try await repository.evidence(id: id),
              record.attemptID == attempt.id,
              case .reading = record.payload
        else { throw DomainError.evidenceNotFound }
        guard record.source == .manual else { throw DomainError.cannotModifyImportedEvidence }
        try await repository.deleteEvidence(id: id)
    }
}

struct GetProgressPhotoUseCase: Sendable {
    let repository: any ChallengeRepository

    func execute(attemptID: UUID, on day: LocalDay) async throws -> RecordedProgressPhoto? {
        try await repository.evidence(attemptID: attemptID, on: day)
            .compactMap(RecordedProgressPhoto.init)
            .max { $0.occurredAt < $1.occurredAt }
    }
}

struct SaveProgressPhotoUseCase: Sendable {
    let repository: any ChallengeRepository
    let photoStore: any ProgressPhotoStore
    let catalog: any ProgramCatalog
    let scheduler: ChallengeScheduler

    func execute(jpegData: Data, occurredAt: Date = .now) async throws -> RecordedProgressPhoto {
        guard !jpegData.isEmpty, jpegData.count <= 20_000_000 else {
            throw DomainError.invalidEvidenceValue
        }
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let program = catalog.program(id: attempt.programID, version: attempt.programVersion) else {
            throw DomainError.persistenceFailure
        }
        let day = LocalDay(occurredAt, calendar: scheduler.calendar(for: attempt))
        guard try scheduler.timing(for: attempt, program: program, on: day).phase == .active else {
            throw DomainError.evidenceOutsideActiveAttempt
        }
        let dailyEvidence = try await repository.evidence(attemptID: attempt.id, on: day)
        let existing = dailyEvidence.first { RecordedProgressPhoto(record: $0) != nil }
        let photoID: UUID
        if let existing,
           case let .progressPhoto(existingPhotoID) = existing.payload {
            photoID = existingPhotoID
        } else {
            photoID = UUID()
        }

        try await photoStore.saveJPEG(jpegData, id: photoID)
        let record = EvidenceRecord(
            id: existing?.id ?? UUID(),
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: occurredAt,
            source: .camera,
            verification: .userReported,
            payload: .progressPhoto(photoRecordID: photoID)
        )
        do {
            try await repository.save(record)
        } catch {
            try? await photoStore.delete(id: photoID)
            throw error
        }
        for manual in dailyEvidence where isManualPhotoCompletion(manual) {
            try await repository.deleteEvidence(id: manual.id)
        }
        guard let photo = RecordedProgressPhoto(record: record) else {
            throw DomainError.persistenceFailure
        }
        return photo
    }

    private func isManualPhotoCompletion(_ record: EvidenceRecord) -> Bool {
        guard case let .manualCompletion(completion) = record.payload else { return false }
        return completion.requirementID == "progress-photo"
    }
}

struct DeleteProgressPhotoUseCase: Sendable {
    let repository: any ChallengeRepository
    let photoStore: any ProgressPhotoStore

    func execute(id: UUID) async throws {
        guard let attempt = try await repository.activeAttempt() else {
            throw DomainError.noActiveChallenge
        }
        guard let record = try await repository.evidence(id: id),
              record.attemptID == attempt.id,
              case let .progressPhoto(photoID) = record.payload
        else { throw DomainError.evidenceNotFound }
        try await photoStore.delete(id: photoID)
        try await repository.deleteEvidence(id: id)
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
        let day = LocalDay(draft.startedAt, calendar: scheduler.calendar(for: attempt))
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
                  reading.pagesRead <= 1_000,
                  reading.bookTitle.map({ (1...200).contains($0.count) }) ?? true
            else { throw DomainError.invalidEvidenceValue }
        case let .manualCompletion(completion):
            let requirementID = completion.requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...100).contains(requirementID.count),
                  (completion.notes?.count ?? 0) <= 500
            else { throw DomainError.invalidEvidenceValue }
        case let .dietCompliance(compliance):
            guard (compliance.notes?.count ?? 0) <= 500 else {
                throw DomainError.invalidEvidenceValue
            }
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
            timeZoneIdentifier: existing.timeZoneIdentifier,
            dietPlan: existing.dietPlan,
            createdAt: now
        )
        try await repository.save(replacement)
        return replacement
    }
}
