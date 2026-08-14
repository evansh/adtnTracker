import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    private let dependencies: DependencyContainer
    @Published private(set) var dashboard: DashboardSnapshot?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var today: LocalDay { LocalDay(.now, calendar: dependencies.calendar) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await dashboardUseCase.execute(on: today)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startChallenge(on day: LocalDay) async {
        do {
            _ = try await StartChallengeUseCase(
                repository: dependencies.repository,
                program: .seventyFiveHard
            ).execute(startedOn: day)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWater(ounces: Int) async {
        let milliliters = Int((Double(ounces) * 29.5735).rounded())
        await record(.hydration(milliliters: milliliters))
    }

    func confirmDiet() async { await record(.diet(isCompliant: true)) }

    func recordReading(bookID: UUID, startingPage: Int, endingPage: Int) async {
        await record(.reading(ReadingEvidence(
            bookID: bookID,
            startingPage: startingPage,
            endingPage: endingPage
        )))
    }

    private var dashboardUseCase: GetDashboardUseCase {
        GetDashboardUseCase(
            repository: dependencies.repository,
            catalog: dependencies.catalog,
            scheduler: ChallengeScheduler(calendar: dependencies.calendar),
            evaluator: RequirementEvaluator()
        )
    }

    private func record(_ payload: EvidencePayload) async {
        do {
            _ = try await RecordEvidenceUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(payload: payload)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
