import Foundation

protocol ChallengeRepository: Sendable {
    func allAttempts() async throws -> [ChallengeAttempt]
    func activeAttempt() async throws -> ChallengeAttempt?
    func save(_ attempt: ChallengeAttempt) async throws
    func evidence(attemptID: UUID, on day: LocalDay) async throws -> [EvidenceRecord]
    func evidence(id: UUID) async throws -> EvidenceRecord?
    func save(_ evidence: EvidenceRecord) async throws
    func deleteEvidence(id: UUID) async throws
}

protocol ProgressPhotoStore: Sendable {
    func saveJPEG(_ data: Data, id: UUID) async throws
    func jpegData(id: UUID) async throws -> Data?
    func delete(id: UUID) async throws
}

protocol GroupRepository: Sendable {
    func allGroups() async throws -> [AccountabilityGroup]
    func group(id: UUID) async throws -> AccountabilityGroup?
    func myGroups(userID: UUID) async throws -> [AccountabilityGroup]
    func save(_ group: AccountabilityGroup) async throws
    func deleteGroup(id: UUID) async throws
    func memberships(userID: UUID) async throws -> [GroupMembership]
    func membership(groupID: UUID, userID: UUID) async throws -> GroupMembership?
    func saveMembership(_ membership: GroupMembership) async throws
    func deleteMembership(groupID: UUID, userID: UUID) async throws
    func members(groupID: UUID) async throws -> [GroupMembership]
    func invites(groupID: UUID) async throws -> [GroupInvite]
    func invite(code: String) async throws -> GroupInvite?
    func saveInvite(_ invite: GroupInvite) async throws
    func useInvite(code: String, userID: UUID) async throws -> GroupMembership
    func activities(groupID: UUID, since: Date?) async throws -> [GroupActivity]
    func saveActivity(_ activity: GroupActivity) async throws
    func reactions(activityID: UUID) async throws -> [GroupReaction]
    func saveReaction(_ reaction: GroupReaction) async throws
    func deleteReaction(activityID: UUID, userID: UUID) async throws
}

protocol ExternalWorkoutService: Sendable {
    func availableSources() -> [ExternalWorkoutSource]
    func requestAuthorization(source: ExternalWorkoutSource) async throws
    func isAuthorized(source: ExternalWorkoutSource) async -> Bool
    func fetchWorkouts(source: ExternalWorkoutSource, since: Date) async throws -> [ExternalWorkout]
    func importWorkout(_ workout: ExternalWorkout, asEvidenceFor attemptID: UUID, on day: LocalDay, slot: WorkoutSlot) async throws -> EvidenceRecord
    func suggestedWorkouts(for attemptID: UUID, on day: LocalDay) async -> [ExternalWorkout]
}

protocol SyncEngine: Sendable {
    var status: SyncStatus { get async }
    func syncNow() async throws
    func registerForBackgroundSync()
}

protocol ProgramCatalog: Sendable {
    func allPrograms() async -> [ProgramDefinition]
    func program(id: String, version: Int) async -> ProgramDefinition?
}
