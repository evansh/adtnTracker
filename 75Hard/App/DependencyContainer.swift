import Foundation

struct DependencyContainer: Sendable {
    let repository: any ChallengeRepository
    let catalog: any ProgramCatalog
    let calendar: Calendar

    static func live() throws -> DependencyContainer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return DependencyContainer(
            repository: try SecureFileChallengeRepository.live(),
            catalog: DefaultProgramCatalog(),
            calendar: calendar
        )
    }

    static func fallback() -> DependencyContainer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return DependencyContainer(
            repository: InMemoryChallengeRepository(),
            catalog: DefaultProgramCatalog(),
            calendar: calendar
        )
    }
}

actor InMemoryChallengeRepository: ChallengeRepository {
    private var attempts: [ChallengeAttempt] = []
    private var records: [EvidenceRecord] = []

    func allAttempts() async throws -> [ChallengeAttempt] { attempts }
    func activeAttempt() async throws -> ChallengeAttempt? { attempts.last { $0.status == .active } }

    func save(_ attempt: ChallengeAttempt) async throws {
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
            attempts[index] = attempt
        } else {
            attempts.append(attempt)
        }
    }

    func evidence(attemptID: UUID, on day: LocalDay) async throws -> [EvidenceRecord] {
        records.filter { $0.attemptID == attemptID && $0.occurredOn == day }
    }

    func save(_ evidence: EvidenceRecord) async throws {
        if let index = records.firstIndex(where: { $0.id == evidence.id }) {
            records[index] = evidence
        } else {
            records.append(evidence)
        }
    }

    func deleteEvidence(id: UUID) async throws { records.removeAll { $0.id == id } }
}
