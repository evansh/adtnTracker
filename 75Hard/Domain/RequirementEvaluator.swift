import Foundation

enum RequirementStatus: String, Equatable, Sendable {
    case complete
    case inProgress
    case notComplete
    case automaticallyVerified

    var isSatisfied: Bool { self == .complete || self == .automaticallyVerified }
}

struct RequirementEvaluation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: RequirementStatus
    let currentValue: Int?
    let targetValue: Int?
    let isManuallyCompleted: Bool

    init(
        id: String,
        title: String,
        status: RequirementStatus,
        currentValue: Int?,
        targetValue: Int?,
        isManuallyCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.isManuallyCompleted = isManuallyCompleted
    }
}

struct DailyEvaluation: Equatable, Sendable {
    let requirements: [RequirementEvaluation]
    var isComplete: Bool { requirements.allSatisfy(\.status.isSatisfied) }
    var completedCount: Int { requirements.filter(\.status.isSatisfied).count }
}

struct RequirementEvaluator: Sendable {
    func evaluate(
        program: ProgramDefinition,
        evidence allEvidence: [EvidenceRecord],
        attemptID: UUID,
        day: LocalDay
    ) -> DailyEvaluation {
        let evidence = allEvidence.filter { $0.attemptID == attemptID && $0.occurredOn == day }
        let results = program.requirements.map { requirement in
            evaluate(requirement: requirement, evidence: evidence)
        }
        return DailyEvaluation(requirements: results)
    }

    private func evaluate(
        requirement: RequirementDefinition,
        evidence: [EvidenceRecord]
    ) -> RequirementEvaluation {
        if evidence.contains(where: { record in
            guard case let .manualCompletion(completion) = record.payload else { return false }
            return completion.requirementID == requirement.id
        }) {
            return RequirementEvaluation(
                id: requirement.id,
                title: requirement.title,
                status: .complete,
                currentValue: targetValue(for: requirement.rule),
                targetValue: targetValue(for: requirement.rule),
                isManuallyCompleted: true
            )
        }

        switch requirement.rule {
        case let .minimumWorkoutCount(target, minimumMinutes):
            let matching = evidence.filter {
                guard case let .workout(workout) = $0.payload else { return false }
                return workout.durationMinutes >= minimumMinutes
            }
            return aggregate(requirement, current: matching.count, target: target, contributing: matching)

        case let .assignedWorkout(slot, minimumMinutes):
            let matching = evidence.filter {
                guard case let .workout(workout) = $0.payload else { return false }
                return workout.assignedSlot == slot && workout.durationMinutes >= minimumMinutes
            }
            return aggregate(requirement, current: matching.isEmpty ? 0 : 1, target: 1, contributing: matching)

        case let .minimumOutdoorWorkoutCount(target, minimumMinutes):
            let matching = evidence.filter {
                guard case let .workout(workout) = $0.payload else { return false }
                return workout.isOutdoor && workout.durationMinutes >= minimumMinutes
            }
            return aggregate(requirement, current: matching.count, target: target, contributing: matching)

        case let .minimumHydration(target):
            let values = evidence.compactMap { record -> (Int, EvidenceRecord)? in
                guard case let .hydration(milliliters) = record.payload else { return nil }
                return (milliliters, record)
            }
            let current = safeSum(values.map(\.0))
            return aggregate(requirement, current: current, target: target, contributing: values.map(\.1))

        case let .minimumReading(target):
            let values = evidence.compactMap { record -> (Int, EvidenceRecord)? in
                guard case let .reading(reading) = record.payload else { return nil }
                return (max(0, reading.pagesRead), record)
            }
            let current = safeSum(values.map(\.0))
            return aggregate(requirement, current: current, target: target, contributing: values.map(\.1))

        case .dietCompliance:
            let confirmations = evidence.filter {
                switch $0.payload {
                case let .diet(isCompliant):
                    isCompliant
                case let .dietCompliance(compliance):
                    compliance.isCompliant
                default:
                    false
                }
            }
            return aggregate(requirement, current: confirmations.isEmpty ? 0 : 1, target: 1, contributing: confirmations)

        case .progressPhoto:
            let photos = evidence.filter {
                guard case .progressPhoto = $0.payload else { return false }
                return true
            }
            return aggregate(requirement, current: photos.isEmpty ? 0 : 1, target: 1, contributing: photos)
        }
    }

    private func targetValue(for rule: RequirementRule) -> Int {
        switch rule {
        case let .minimumWorkoutCount(target, _),
             let .minimumOutdoorWorkoutCount(target, _):
            target
        case .assignedWorkout:
            1
        case let .minimumHydration(target):
            target
        case let .minimumReading(target):
            target
        case .dietCompliance, .progressPhoto:
            1
        }
    }

    private func aggregate(
        _ requirement: RequirementDefinition,
        current: Int,
        target: Int,
        contributing: [EvidenceRecord]
    ) -> RequirementEvaluation {
        let status: RequirementStatus
        if current >= target {
            let automaticallyVerified = !contributing.isEmpty && contributing.allSatisfy {
                $0.source.isAutomaticVerification && $0.verification == .sourceVerified
            }
            status = automaticallyVerified ? .automaticallyVerified : .complete
        } else {
            status = current > 0 ? .inProgress : .notComplete
        }
        return RequirementEvaluation(
            id: requirement.id,
            title: requirement.title,
            status: status,
            currentValue: current,
            targetValue: target
        )
    }

    private func safeSum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int.max : max(0, sum)
        }
    }
}
