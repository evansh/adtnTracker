import XCTest
@testable import Hard75

final class SecureFileChallengeRepositoryTests: XCTestCase {
    private struct LegacyChallengeAttempt: Encodable {
        let id: UUID
        let programID: String
        let programVersion: Int
        let startedOn: LocalDay
        let status: ChallengeAttemptStatus
        let createdAt: Date
    }

    func testLegacyAttemptDecodesWithoutTimezoneOrDietPlan() throws {
        let legacy = LegacyChallengeAttempt(
            id: UUID(),
            programID: "75-hard",
            programVersion: 1,
            startedOn: LocalDay(year: 2026, month: 8, day: 14),
            status: .active,
            createdAt: .now
        )
        let data = try JSONEncoder().encode(legacy)

        let attempt = try JSONDecoder().decode(ChallengeAttempt.self, from: data)

        XCTAssertNil(attempt.timeZoneIdentifier)
        XCTAssertNil(attempt.dietPlan)
    }

    func testLegacyWorkoutPayloadDecodesWithoutNewAssignmentMetadata() throws {
        let data = Data(#"{"type":"Walk","durationMinutes":45,"isOutdoor":true,"distanceMeters":null}"#.utf8)

        let workout = try JSONDecoder().decode(WorkoutEvidence.self, from: data)

        XCTAssertEqual(workout.type, "Walk")
        XCTAssertNil(workout.assignedSlot)
        XCTAssertNil(workout.notes)
    }

    func testLegacyReadingPayloadDecodesWithoutBookTitle() throws {
        let bookID = UUID()
        let data = Data("""
        {"bookID":"\(bookID.uuidString)","startingPage":10,"endingPage":20}
        """.utf8)

        let reading = try JSONDecoder().decode(ReadingEvidence.self, from: data)

        XCTAssertEqual(reading.bookID, bookID)
        XCTAssertNil(reading.bookTitle)
    }

    func testStateRoundTripsAcrossRepositoryInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SecureFileChallengeRepository(fileURL: fileURL)
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attempt = ChallengeAttempt(
            programID: ProgramDefinition.seventyFiveHard.id,
            programVersion: 1,
            startedOn: day
        )
        let evidence = EvidenceRecord(
            attemptID: attempt.id,
            occurredOn: day,
            occurredAt: Date(timeIntervalSince1970: 1_786_665_600),
            source: .manual,
            verification: .userReported,
            payload: .hydration(milliliters: 473)
        )
        try await first.save(attempt)
        try await first.save(evidence)

        let second = SecureFileChallengeRepository(fileURL: fileURL)
        let restoredAttempt = try await second.activeAttempt()
        let restoredEvidence = try await second.evidence(attemptID: attempt.id, on: day)
        XCTAssertEqual(restoredAttempt?.id, attempt.id)
        XCTAssertEqual(restoredEvidence, [evidence])
    }

    func testExternalEvidenceIsDeduplicatedBySourceAndID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SecureFileChallengeRepository(fileURL: fileURL)
        let day = LocalDay(year: 2026, month: 8, day: 14)
        let attemptID = UUID()
        let record = EvidenceRecord(
            attemptID: attemptID,
            occurredOn: day,
            occurredAt: .now,
            source: .strava,
            verification: .sourceVerified,
            externalID: "activity-123",
            payload: .workout(WorkoutEvidence(type: "Run", durationMinutes: 45, isOutdoor: true, distanceMeters: 7_000))
        )

        try await repository.save(record)
        try await repository.save(EvidenceRecord(
            attemptID: attemptID,
            occurredOn: day,
            occurredAt: .now,
            source: .strava,
            verification: .sourceVerified,
            externalID: "activity-123",
            payload: record.payload
        ))

        let savedEvidence = try await repository.evidence(attemptID: attemptID, on: day)
        XCTAssertEqual(savedEvidence.count, 1)
    }
}
