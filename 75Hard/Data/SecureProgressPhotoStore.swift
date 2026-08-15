import Foundation

actor SecureProgressPhotoStore: ProgressPhotoStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func live() throws -> SecureProgressPhotoStore {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return SecureProgressPhotoStore(
            directoryURL: root
                .appending(path: "75Hard", directoryHint: .isDirectory)
                .appending(path: "ProgressPhotos", directoryHint: .isDirectory)
        )
    }

    func saveJPEG(_ data: Data, id: UUID) async throws {
        guard !data.isEmpty, data.count <= 20_000_000 else {
            throw DomainError.invalidEvidenceValue
        }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(
                to: fileURL(for: id),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            throw DomainError.persistenceFailure
        }
    }

    func jpegData(id: UUID) async throws -> Data? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DomainError.persistenceFailure
        }
    }

    func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw DomainError.persistenceFailure
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appending(path: id.uuidString + ".jpg", directoryHint: .notDirectory)
    }
}
