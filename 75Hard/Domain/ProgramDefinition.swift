import Foundation

enum RequirementRule: Codable, Equatable, Sendable {
    case minimumWorkoutCount(Int, minimumMinutes: Int)
    case minimumOutdoorWorkoutCount(Int, minimumMinutes: Int)
    case minimumHydration(milliliters: Int)
    case minimumReading(pages: Int)
    case dietCompliance
    case progressPhoto
}

struct RequirementDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let rule: RequirementRule
}

struct ProgramDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let version: Int
    let name: String
    let durationDays: Int
    let requirements: [RequirementDefinition]
}

extension ProgramDefinition {
    static let seventyFiveHard = ProgramDefinition(
        id: "75-hard",
        version: 1,
        name: "75 Hard",
        durationDays: 75,
        requirements: [
            RequirementDefinition(
                id: "workout-1",
                title: "Workout #1",
                rule: .minimumWorkoutCount(1, minimumMinutes: 45)
            ),
            RequirementDefinition(
                id: "workout-2",
                title: "Workout #2",
                rule: .minimumWorkoutCount(2, minimumMinutes: 45)
            ),
            RequirementDefinition(
                id: "outdoor-workout",
                title: "Outdoor Workout",
                rule: .minimumOutdoorWorkoutCount(1, minimumMinutes: 45)
            ),
            RequirementDefinition(
                id: "diet",
                title: "Follow Diet",
                rule: .dietCompliance
            ),
            RequirementDefinition(
                id: "water",
                title: "Drink 1 Gallon",
                rule: .minimumHydration(milliliters: 3_785)
            ),
            RequirementDefinition(
                id: "reading",
                title: "Read 10 Pages",
                rule: .minimumReading(pages: 10)
            ),
            RequirementDefinition(
                id: "progress-photo",
                title: "Progress Photo",
                rule: .progressPhoto
            ),
        ]
    )
}

protocol ProgramCatalog: Sendable {
    func program(id: String, version: Int) -> ProgramDefinition?
}

struct DefaultProgramCatalog: ProgramCatalog {
    func program(id: String, version: Int) -> ProgramDefinition? {
        let program = ProgramDefinition.seventyFiveHard
        return program.id == id && program.version == version ? program : nil
    }
}
