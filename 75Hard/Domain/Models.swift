import Foundation

struct LocalDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(in calendar: Calendar) throws -> Date {
        let requested = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: requested) else {
            throw DomainError.invalidLocalDay
        }
        let startOfDay = calendar.startOfDay(for: date)
        let resolved = calendar.dateComponents([.year, .month, .day], from: startOfDay)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            throw DomainError.invalidLocalDay
        }
        return startOfDay
    }
}

enum DomainError: Error, Equatable, LocalizedError {
    case activeChallengeAlreadyExists
    case noActiveChallenge
    case invalidLocalDay
    case invalidEvidenceValue
    case evidenceOutsideActiveAttempt
    case invalidRestartDate
    case invalidProgramDefinition
    case evidenceNotFound
    case workoutSlotAlreadyAssigned
    case cannotModifyImportedEvidence
    case persistenceFailure

    var errorDescription: String? {
        switch self {
        case .activeChallengeAlreadyExists: "An active challenge already exists."
        case .noActiveChallenge: "There is no active challenge."
        case .invalidLocalDay: "The selected calendar day is invalid."
        case .invalidEvidenceValue: "The entry contains an invalid value."
        case .evidenceOutsideActiveAttempt: "Evidence must belong to the active challenge window."
        case .invalidRestartDate: "A restart must begin after the failed day."
        case .invalidProgramDefinition: "The challenge program definition is invalid."
        case .evidenceNotFound: "The selected entry could not be found."
        case .workoutSlotAlreadyAssigned: "That workout slot already has an entry for this day."
        case .cannotModifyImportedEvidence: "Imported evidence must be managed by its source."
        case .persistenceFailure: "The challenge state could not be saved securely."
        }
    }
}

enum ChallengeAttemptStatus: Codable, Equatable, Sendable {
    case active
    case failed(failedOn: LocalDay, unmetRequirementIDs: [String])
    case completed(completedOn: LocalDay)
}

struct DietPlan: Codable, Equatable, Sendable {
    var name: String
    var rules: String
}

struct ChallengeAttempt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let programID: String
    let programVersion: Int
    let startedOn: LocalDay
    let timeZoneIdentifier: String?
    var dietPlan: DietPlan?
    var status: ChallengeAttemptStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        programID: String,
        programVersion: Int,
        startedOn: LocalDay,
        timeZoneIdentifier: String? = nil,
        dietPlan: DietPlan? = nil,
        status: ChallengeAttemptStatus = .active,
        createdAt: Date = .now
    ) {
        self.id = id
        self.programID = programID
        self.programVersion = programVersion
        self.startedOn = startedOn
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dietPlan = dietPlan
        self.status = status
        self.createdAt = createdAt
    }
}

enum EvidenceSource: String, Codable, Sendable {
    case manual
    case camera
    case appleHealth
    case strava

    var isAutomaticVerification: Bool {
        self == .appleHealth || self == .strava
    }
}

enum VerificationStatus: String, Codable, Sendable {
    case userReported
    case sourceVerified
}

struct WorkoutEvidence: Codable, Equatable, Sendable {
    let type: String
    let durationMinutes: Int
    let isOutdoor: Bool
    let distanceMeters: Double?
    let assignedSlot: WorkoutSlot?
    let notes: String?

    init(
        type: String,
        durationMinutes: Int,
        isOutdoor: Bool,
        distanceMeters: Double?,
        assignedSlot: WorkoutSlot? = nil,
        notes: String? = nil
    ) {
        self.type = type
        self.durationMinutes = durationMinutes
        self.isOutdoor = isOutdoor
        self.distanceMeters = distanceMeters
        self.assignedSlot = assignedSlot
        self.notes = notes
    }
}

/// Stable, platform-neutral identifiers used by iOS, a future API, and Android.
enum WorkoutSlot: String, Codable, CaseIterable, Equatable, Sendable {
    case first = "workout-1"
    case second = "workout-2"
}

struct ReadingEvidence: Codable, Equatable, Sendable {
    let bookID: UUID
    let startingPage: Int
    let endingPage: Int
    let bookTitle: String?

    init(
        bookID: UUID,
        startingPage: Int,
        endingPage: Int,
        bookTitle: String? = nil
    ) {
        self.bookID = bookID
        self.startingPage = startingPage
        self.endingPage = endingPage
        self.bookTitle = bookTitle
    }

    var pagesRead: Int { endingPage - startingPage }
}

struct ManualCompletionEvidence: Codable, Equatable, Sendable {
    let requirementID: String
    let notes: String?
}

struct DietComplianceEvidence: Codable, Equatable, Sendable {
    let isCompliant: Bool
    let notes: String?
}

enum EvidencePayload: Codable, Equatable, Sendable {
    case workout(WorkoutEvidence)
    case hydration(milliliters: Int)
    case reading(ReadingEvidence)
    case diet(isCompliant: Bool)
    case dietCompliance(DietComplianceEvidence)
    case progressPhoto(photoRecordID: UUID)
    case manualCompletion(ManualCompletionEvidence)
}

struct EvidenceRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let attemptID: UUID
    let occurredOn: LocalDay
    let occurredAt: Date
    let source: EvidenceSource
    let verification: VerificationStatus
    let externalID: String?
    let payload: EvidencePayload

    init(
        id: UUID = UUID(),
        attemptID: UUID,
        occurredOn: LocalDay,
        occurredAt: Date,
        source: EvidenceSource,
        verification: VerificationStatus,
        externalID: String? = nil,
        payload: EvidencePayload
    ) {
        self.id = id
        self.attemptID = attemptID
        self.occurredOn = occurredOn
        self.occurredAt = occurredAt
        self.source = source
        self.verification = verification
        self.externalID = externalID
        self.payload = payload
    }
}

struct RecordedWorkout: Identifiable, Equatable, Sendable {
    let id: UUID
    let attemptID: UUID
    let occurredOn: LocalDay
    let occurredAt: Date
    let source: EvidenceSource
    let verification: VerificationStatus
    let workout: WorkoutEvidence

    var canEdit: Bool { source == .manual }

    init?(record: EvidenceRecord) {
        guard case let .workout(workout) = record.payload else { return nil }
        id = record.id
        attemptID = record.attemptID
        occurredOn = record.occurredOn
        occurredAt = record.occurredAt
        source = record.source
        verification = record.verification
        self.workout = workout
    }
}

struct RecordedHydration: Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let source: EvidenceSource
    let milliliters: Int

    var canEdit: Bool { source == .manual }

    init?(record: EvidenceRecord) {
        guard case let .hydration(milliliters) = record.payload else { return nil }
        id = record.id
        occurredAt = record.occurredAt
        source = record.source
        self.milliliters = milliliters
    }
}

struct RecordedDietCompliance: Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let isCompliant: Bool
    let notes: String?

    init?(record: EvidenceRecord) {
        switch record.payload {
        case let .diet(isCompliant):
            id = record.id
            occurredAt = record.occurredAt
            self.isCompliant = isCompliant
            notes = nil
        case let .dietCompliance(compliance):
            id = record.id
            occurredAt = record.occurredAt
            isCompliant = compliance.isCompliant
            notes = compliance.notes
        default:
            return nil
        }
    }
}

struct RecordedReading: Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let source: EvidenceSource
    let reading: ReadingEvidence

    var canEdit: Bool { source == .manual }

    init?(record: EvidenceRecord) {
        guard case let .reading(reading) = record.payload else { return nil }
        id = record.id
        occurredAt = record.occurredAt
        source = record.source
        self.reading = reading
    }
}

struct RecordedProgressPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let photoRecordID: UUID
    let occurredAt: Date

    init?(record: EvidenceRecord) {
        guard case let .progressPhoto(photoRecordID) = record.payload else { return nil }
        id = record.id
        self.photoRecordID = photoRecordID
        occurredAt = record.occurredAt
    }
}

struct Book: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

struct ProgressPhotoMetadata: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let attemptID: UUID
    let capturedOn: LocalDay
    let capturedAt: Date
    let challengeDay: Int
}

struct PrivacySettings: Codable, Equatable, Sendable {
    var sharesCompletionStatus = false
    var sharesWorkoutDetails = false
    var sharesWorkoutLocation = false
    var sharesReading = false
    var sharesDiet = false
    var sharesHydration = false
    var sharesProgressPhotos = false
}

struct AppUser: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var privacy: PrivacySettings
}

enum GroupRole: String, Codable, Sendable { case owner, member }
enum GroupVisibility: String, Codable, Sendable { case privateGroup, publicGroup }

struct AccountabilityGroup: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var details: String
    var visibility: GroupVisibility
    var startDate: LocalDay
}

struct GroupMembership: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let userID: UUID
    var role: GroupRole
}
