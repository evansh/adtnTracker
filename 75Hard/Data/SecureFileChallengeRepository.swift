import Foundation

actor SecureFileChallengeRepository: ChallengeRepository {
    private struct PersistedState: Codable {
        var attempts: [ChallengeAttempt] = []
        var evidence: [EvidenceRecord] = []
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var cachedState: PersistedState?

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) throws -> SecureFileChallengeRepository {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return SecureFileChallengeRepository(
            fileURL: root.appending(path: "75Hard", directoryHint: .isDirectory)
                .appending(path: "challenge-state.json", directoryHint: .notDirectory),
            fileManager: fileManager
        )
    }

    func allAttempts() async throws -> [ChallengeAttempt] {
        try load().attempts.sorted { $0.createdAt < $1.createdAt }
    }

    func activeAttempt() async throws -> ChallengeAttempt? {
        try load().attempts.last { $0.status == .active }
    }

    func save(_ attempt: ChallengeAttempt) async throws {
        var state = try load()
        if let index = state.attempts.firstIndex(where: { $0.id == attempt.id }) {
            state.attempts[index] = attempt
        } else {
            state.attempts.append(attempt)
        }
        try persist(state)
    }

    func evidence(attemptID: UUID, on day: LocalDay) async throws -> [EvidenceRecord] {
        try load().evidence.filter { $0.attemptID == attemptID && $0.occurredOn == day }
    }

    func save(_ evidence: EvidenceRecord) async throws {
        var state = try load()

        if let externalID = evidence.externalID,
           state.evidence.contains(where: { $0.source == evidence.source && $0.externalID == externalID }) {
            return
        }

        if let index = state.evidence.firstIndex(where: { $0.id == evidence.id }) {
            state.evidence[index] = evidence
        } else {
            state.evidence.append(evidence)
        }
        try persist(state)
    }

    func deleteEvidence(id: UUID) async throws {
        var state = try load()
        state.evidence.removeAll { $0.id == id }
        try persist(state)
    }

    private func load() throws -> PersistedState {
        if let cachedState { return cachedState }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let empty = PersistedState()
            cachedState = empty
            return empty
        }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let state = try JSONDecoder.securePersistence.decode(PersistedState.self, from: data)
            cachedState = state
            return state
        } catch {
            throw DomainError.persistenceFailure
        }
    }

    private func persist(_ state: PersistedState) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)

            let data = try JSONEncoder.securePersistence.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            cachedState = state
        } catch {
            throw DomainError.persistenceFailure
        }
    }
}

private extension JSONEncoder {
    static var securePersistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var securePersistence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
