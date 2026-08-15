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
