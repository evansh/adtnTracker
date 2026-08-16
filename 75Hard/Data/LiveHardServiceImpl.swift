import Foundation

actor LiveHardServiceImpl: LiveHardService {
    private let repository: any ChallengeRepository
    private var currentProgram: LiveHardProgram?

    init(repository: any ChallengeRepository) {
        self.repository = repository
    }

    static func live(repository: any ChallengeRepository) -> LiveHardServiceImpl {
        LiveHardServiceImpl(repository: repository)
    }

    func currentProgram() async -> LiveHardProgram? {
        if let program = currentProgram { return program }
        let attempts = try? await repository.allAttempts()
        guard let lastAttempt = attempts?.last else { return nil }
        let phase = LiveHardPhase(rawValue: lastAttempt.programID) ?? .phase1
        let completed = (try? await repository.allAttempts())?.filter { $0.status == .completed }.map { LiveHardPhase(rawValue: $0.programID) }.compactMap { $0 } ?? []
        currentProgram = LiveHardProgram(phase: phase, startedOn: lastAttempt.startedOn, currentPhaseStartDate: lastAttempt.startedOn, completedPhases: completed)
        return currentProgram
    }

    func startPhase(_ phase: LiveHardPhase) async throws {
        let startDay = LocalDay(Date(), calendar: Calendar.current)
        let programDef = getProgramDefinition(for: phase)
        let attempt = ChallengeAttempt(programID: programDef.id, programVersion: programDef.version, startedOn: startDay)
        try await repository.save(attempt)
        currentProgram = LiveHardProgram(phase: phase, startedOn: startDay, currentPhaseStartDate: startDay, completedPhases: currentProgram?.completedPhases ?? [])
    }

    func completePhase(_ phase: LiveHardPhase) async throws {
        currentProgram?.completedPhases.append(phase)
        if let next = currentProgram?.nextPhase {
            try await startPhase(next)
        }
    }

    func getProgramDefinition(for phase: LiveHardPhase) -> ProgramDefinition {
        let baseRequirements = [
            Requirement(id: "workout-1", title: "Workout #1", detail: "45 minutes", kind: .workout(slot: .first)),
            Requirement(id: "workout-2", title: "Workout #2", detail: "45 minutes (outdoor)", kind: .workout(slot: .second)),
            Requirement(id: "water", title: "Water", detail: "1 gallon", kind: .hydration(targetMilliliters: 3785)),
            Requirement(id: "reading", title: "Reading", detail: "10 pages", kind: .reading(targetPages: 10)),
            Requirement(id: "diet", title: "Diet", detail: "Follow your diet", kind: .diet),
            Requirement(id: "progress-photo", title: "Progress Photo", detail: "Daily photo", kind: .progressPhoto)
        ]

        var additional: [Requirement] = []
        for reqID in phase.additionalRequirements {
            switch reqID {
            case "visualization-10min":
                additional.append(Requirement(id: reqID, title: "Visualization", detail: "10 minutes", kind: .manual))
            case "cold-shower":
                additional.append(Requirement(id: reqID, title: "Cold Shower", detail: "5 minutes", kind: .manual))
            case "meditation-10min":
                additional.append(Requirement(id: reqID, title: "Meditation", detail: "10 minutes", kind: .manual))
            case "random-act-kindness":
                additional.append(Requirement(id: reqID, title: "Random Act of Kindness", detail: "1 per day", kind: .manual))
            case "no-alcohol-cheat":
                additional.append(Requirement(id: reqID, title: "No Alcohol/Cheat Meals", detail: "Strict compliance", kind: .diet))
            default:
                break
            }
        }

        return ProgramDefinition(id: phase.rawValue, version: 1, name: phase.displayName, durationDays: phase.durationDays, requirements: baseRequirements + additional)
    }
}