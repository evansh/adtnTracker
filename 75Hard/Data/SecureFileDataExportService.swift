import Foundation

actor SecureFileDataExportService: DataExportService {
    private let repository: any ChallengeRepository
    private let groupRepository: any GroupRepository
    private let photoStore: any ProgressPhotoStore
    private let fileURL: URL

    init(repository: any ChallengeRepository, groupRepository: any GroupRepository, photoStore: any ProgressPhotoStore, fileURL: URL) {
        self.repository = repository
        self.groupRepository = groupRepository
        self.photoStore = photoStore
        self.fileURL = fileURL
    }

    static func live() throws -> SecureFileDataExportService {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let repository = try SecureFileChallengeRepository.live()
        let groupRepository = try SecureFileGroupRepository.live()
        let photoStore = try SecureProgressPhotoStore.live()
        return SecureFileDataExportService(
            repository: repository,
            groupRepository: groupRepository,
            photoStore: photoStore,
            fileURL: root.appending(path: "75Hard", directoryHint: .isDirectory).appending(path: "exports", directoryHint: .isDirectory)
        )
    }

    func exportAllData() async throws -> DataExport {
        let attempts = try await repository.allAttempts()
        let evidence = try await allEvidence(for: attempts)
        let books = try await allBooks(for: attempts)
        let progressPhotos = try await allProgressPhotos(for: attempts)
        let groups = try await groupRepository.allGroups()
        let memberships = try await allMemberships()
        let user = AppUser(id: UUID(), displayName: "User", privacy: PrivacySettings())
        let notificationPreferences = UserNotificationPreferences.default
        let privacySettings = PrivacySettings()

        return DataExport(
            user: user,
            attempts: attempts,
            evidence: evidence,
            books: books,
            progressPhotos: progressPhotos,
            groups: groups,
            memberships: memberships,
            notificationPreferences: notificationPreferences,
            privacySettings: privacySettings,
            exportedAt: Date(),
            exportVersion: 1
        )
    }

    func importData(_ export: DataExport) async throws {
        for attempt in export.attempts {
            try await repository.save(attempt)
        }
        for record in export.evidence {
            try await repository.save(record)
        }
        for group in export.groups {
            try await groupRepository.save(group)
        }
        for membership in export.memberships {
            try await groupRepository.saveMembership(membership)
        }
    }

    func deleteAllUserData() async throws {
        let attempts = try await repository.allAttempts()
        for attempt in attempts {
            let evidence = try await allEvidence(for: [attempt])
            for record in evidence {
                try await repository.deleteEvidence(id: record.id)
            }
        }
        let groups = try await groupRepository.allGroups()
        for group in groups {
            try await groupRepository.deleteGroup(id: group.id)
        }
    }

    private func allEvidence(for attempts: [ChallengeAttempt]) async throws -> [EvidenceRecord] {
        var all: [EvidenceRecord] = []
        for attempt in attempts {
            for dayOffset in 0..<75 {
                if let day = try? Calendar.current.date(byAdding: .day, value: dayOffset, to: attempt.startedOn.date(in: Calendar.current)) {
                    let localDay = LocalDay(day, calendar: Calendar.current)
                    let dayEvidence = try await repository.evidence(attemptID: attempt.id, on: localDay)
                    all.append(contentsOf: dayEvidence)
                }
            }
        }
        return all
    }

    private func allBooks(for attempts: [ChallengeAttempt]) async throws -> [Book] {
        var books: [Book] = []
        for attempt in attempts {
            for dayOffset in 0..<75 {
                if let day = try? Calendar.current.date(byAdding: .day, value: dayOffset, to: attempt.startedOn.date(in: Calendar.current)) {
                    let localDay = LocalDay(day, calendar: Calendar.current)
                    let dayEvidence = try await repository.evidence(attemptID: attempt.id, on: localDay)
                    for record in dayEvidence {
                        if case let .reading(reading) = record.payload {
                            let book = Book(id: reading.bookID, title: reading.bookTitle ?? "Unknown", isCompleted: false)
                            if !books.contains(where: { $0.id == book.id }) {
                                books.append(book)
                            }
                        }
                    }
                }
            }
        }
        return books
    }

    private func allProgressPhotos(for attempts: [ChallengeAttempt]) async throws -> [ProgressPhotoMetadata] {
        var photos: [ProgressPhotoMetadata] = []
        for attempt in attempts {
            for dayOffset in 0..<75 {
                if let day = try? Calendar.current.date(byAdding: .day, value: dayOffset, to: attempt.startedOn.date(in: Calendar.current)) {
                    let localDay = LocalDay(day, calendar: Calendar.current)
                    let dayEvidence = try await repository.evidence(attemptID: attempt.id, on: localDay)
                    for record in dayEvidence {
                        if case let .progressPhoto(photoRecordID) = record.payload {
                            photos.append(ProgressPhotoMetadata(id: record.id, attemptID: attempt.id, capturedOn: localDay, capturedAt: record.occurredAt, challengeDay: dayOffset + 1))
                        }
                    }
                }
            }
        }
        return photos
    }

    private func allMemberships() async throws -> [GroupMembership] {
        let groups = try await groupRepository.allGroups()
        var all: [GroupMembership] = []
        for group in groups {
            all.append(contentsOf: try await groupRepository.members(groupID: group.id))
        }
        return all
    }
}