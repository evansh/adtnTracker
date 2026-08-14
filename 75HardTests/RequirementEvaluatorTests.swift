import XCTest
@testable import Hard75

final class RequirementEvaluatorTests: XCTestCase {
    private let attemptID = UUID()
    private let day = LocalDay(year: 2026, month: 8, day: 14)

    func testAllRequirementsMustPassBeforeDayCompletes() {
        let evidence = [
            record(.workout(WorkoutEvidence(type: "Walk", durationMinutes: 45, isOutdoor: true, distanceMeters: nil, assignedSlot: .first))),
            record(.workout(WorkoutEvidence(type: "Strength", durationMinutes: 45, isOutdoor: false, distanceMeters: nil, assignedSlot: .second))),
            record(.hydration(milliliters: 3_000)),
            record(.reading(ReadingEvidence(bookID: UUID(), startingPage: 10, endingPage: 20))),
            record(.diet(isCompliant: true)),
            record(.progressPhoto(photoRecordID: UUID()), source: .camera),
        ]

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: evidence,
            attemptID: attemptID,
            day: day
        )

        XCTAssertFalse(evaluation.isComplete)
        XCTAssertEqual(evaluation.completedCount, 6)
        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "water" })?.status, .inProgress)
    }

    func testCompleteDayUsesNormalizedEvidence() {
        let evidence = [
            record(.workout(WorkoutEvidence(type: "Walk", durationMinutes: 45, isOutdoor: true, distanceMeters: nil, assignedSlot: .first))),
            record(.workout(WorkoutEvidence(type: "Strength", durationMinutes: 60, isOutdoor: false, distanceMeters: nil, assignedSlot: .second))),
            record(.hydration(milliliters: 2_000)),
            record(.hydration(milliliters: 1_785)),
            record(.reading(ReadingEvidence(bookID: UUID(), startingPage: 0, endingPage: 10))),
            record(.diet(isCompliant: true)),
            record(.progressPhoto(photoRecordID: UUID()), source: .camera),
        ]

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: evidence,
            attemptID: attemptID,
            day: day
        )

        XCTAssertTrue(evaluation.isComplete)
        XCTAssertEqual(evaluation.completedCount, 7)
    }

    func testVerifiedProviderEvidenceGetsDistinctStatus() {
        let workout = record(
            .workout(WorkoutEvidence(type: "Run", durationMinutes: 50, isOutdoor: true, distanceMeters: 8_000, assignedSlot: .first)),
            source: .appleHealth,
            verification: .sourceVerified
        )

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: [workout],
            attemptID: attemptID,
            day: day
        )

        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "workout-1" })?.status, .automaticallyVerified)
        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "outdoor-workout" })?.status, .automaticallyVerified)
    }

    func testAssignedWorkoutOnlyCompletesItsOwnSlot() {
        let workout = record(.workout(WorkoutEvidence(
            type: "Walk",
            durationMinutes: 45,
            isOutdoor: true,
            distanceMeters: nil,
            assignedSlot: .first
        )))

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: [workout],
            attemptID: attemptID,
            day: day
        )

        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "workout-1" })?.status, .complete)
        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "workout-2" })?.status, .notComplete)
        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "outdoor-workout" })?.status, .complete)
    }

    func testEvidenceFromAnotherDayOrAttemptIsIgnored() {
        let wrongAttempt = EvidenceRecord(
            attemptID: UUID(),
            occurredOn: day,
            occurredAt: .now,
            source: .manual,
            verification: .userReported,
            payload: .hydration(milliliters: 4_000)
        )
        let wrongDay = EvidenceRecord(
            attemptID: attemptID,
            occurredOn: LocalDay(year: 2026, month: 8, day: 13),
            occurredAt: .now,
            source: .manual,
            verification: .userReported,
            payload: .hydration(milliliters: 4_000)
        )

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: [wrongAttempt, wrongDay],
            attemptID: attemptID,
            day: day
        )

        XCTAssertEqual(evaluation.requirements.first(where: { $0.id == "water" })?.status, .notComplete)
    }

    func testManualCompletionSatisfiesRequirementWithoutIntegration() {
        let evidence = record(.manualCompletion(ManualCompletionEvidence(
            requirementID: "reading",
            notes: nil
        )))

        let evaluation = RequirementEvaluator().evaluate(
            program: .seventyFiveHard,
            evidence: [evidence],
            attemptID: attemptID,
            day: day
        )
        let reading = evaluation.requirements.first { $0.id == "reading" }

        XCTAssertEqual(reading?.status, .complete)
        XCTAssertEqual(reading?.currentValue, 10)
        XCTAssertTrue(reading?.isManuallyCompleted == true)
    }

    private func record(
        _ payload: EvidencePayload,
        source: EvidenceSource = .manual,
        verification: VerificationStatus = .userReported
    ) -> EvidenceRecord {
        EvidenceRecord(
            attemptID: attemptID,
            occurredOn: day,
            occurredAt: .now,
            source: source,
            verification: verification,
            payload: payload
        )
    }
}
