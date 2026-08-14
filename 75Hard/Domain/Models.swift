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
        case .persistenceFailure: "The challenge state could not be saved securely."
        }
    }
}

enum ChallengeAttemptStatus: Codable, Equatable, Sendable {
    case active
    case failed(failedOn: LocalDay, unmetRequirementIDs: [String])
    case completed(completedOn: LocalDay)
}

struct ChallengeAttempt: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let programID: String
    let programVersion: Int
    let startedOn: LocalDay
    var status: ChallengeAttemptStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        programID: String,
        programVersion: Int,
        startedOn: LocalDay,
        status: ChallengeAttemptStatus = .active,
        createdAt: Date = .now
    ) {
        self.id = id
        self.programID = programID
        self.programVersion = programVersion
        self.startedOn = startedOn
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
}

struct ReadingEvidence: Codable, Equatable, Sendable {
    let bookID: UUID
    let startingPage: Int
    let endingPage: Int

    var pagesRead: Int { endingPage - startingPage }
}

enum EvidencePayload: Codable, Equatable, Sendable {
    case workout(WorkoutEvidence)
    case hydration(milliliters: Int)
    case reading(ReadingEvidence)
    case diet(isCompliant: Bool)
    case progressPhoto(photoRecordID: UUID)
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
