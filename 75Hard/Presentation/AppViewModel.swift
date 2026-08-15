import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    private let dependencies: DependencyContainer
    @Published private(set) var dashboard: DashboardSnapshot?
    @Published private(set) var workouts: [RecordedWorkout] = []
    @Published private(set) var hydrationEntries: [RecordedHydration] = []
    @Published private(set) var dietCompliance: RecordedDietCompliance?
    @Published private(set) var readingEntries: [RecordedReading] = []
    @Published private(set) var progressPhoto: RecordedProgressPhoto?
    @Published private(set) var progressPhotoData: Data?
    @Published private(set) var incompleteDayReview: IncompleteDayReview?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await dashboardUseCase.execute()
            incompleteDayReview = try await FindFirstIncompleteDayUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar),
                evaluator: RequirementEvaluator()
            ).execute()
            if let snapshot = dashboard {
                workouts = try await ListRecordedWorkoutsUseCase(
                    repository: dependencies.repository
                ).execute(on: snapshot.day)
                hydrationEntries = try await ListHydrationUseCase(
                    repository: dependencies.repository
                ).execute(attemptID: snapshot.attempt.id, on: snapshot.day)
                dietCompliance = try await GetDietComplianceUseCase(
                    repository: dependencies.repository
                ).execute(attemptID: snapshot.attempt.id, on: snapshot.day)
                readingEntries = try await ListReadingUseCase(
                    repository: dependencies.repository
                ).execute(attemptID: snapshot.attempt.id, on: snapshot.day)
                progressPhoto = try await GetProgressPhotoUseCase(
                    repository: dependencies.repository
                ).execute(attemptID: snapshot.attempt.id, on: snapshot.day)
                if let photoID = progressPhoto?.photoRecordID {
                    progressPhotoData = try await dependencies.photoStore.jpegData(id: photoID)
                } else {
                    progressPhotoData = nil
                }
            } else {
                workouts = []
                hydrationEntries = []
                dietCompliance = nil
                readingEntries = []
                progressPhoto = nil
                progressPhotoData = nil
            }
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
            ).execute(
                startedOn: day,
                timeZoneIdentifier: dependencies.calendar.timeZone.identifier
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWater(ounces: Int) async {
        let milliliters = Int((Double(ounces) * 29.5735).rounded())
        _ = await saveHydration(milliliters: milliliters)
    }

    @discardableResult
    func saveHydration(id: UUID? = nil, milliliters: Int) async -> Bool {
        do {
            _ = try await SaveManualHydrationUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(id: id, milliliters: milliliters)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteHydration(id: UUID) async {
        do {
            try await DeleteManualHydrationUseCase(
                repository: dependencies.repository
            ).execute(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configureDiet(name: String, rules: String) async -> Bool {
        do {
            _ = try await ConfigureDietPlanUseCase(
                repository: dependencies.repository
            ).execute(name: name, rules: rules)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setDietCompliance(isCompliant: Bool, notes: String?) async -> Bool {
        do {
            _ = try await SetDietComplianceUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(isCompliant: isCompliant, notes: notes)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveReading(
        id: UUID? = nil,
        bookID: UUID? = nil,
        bookTitle: String,
        startingPage: Int,
        endingPage: Int
    ) async -> Bool {
        do {
            _ = try await SaveManualReadingUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(
                id: id,
                bookID: bookID,
                bookTitle: bookTitle,
                startingPage: startingPage,
                endingPage: endingPage
            )
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteReading(id: UUID) async {
        do {
            try await DeleteManualReadingUseCase(
                repository: dependencies.repository
            ).execute(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProgressPhoto(jpegData: Data) async -> Bool {
        do {
            _ = try await SaveProgressPhotoUseCase(
                repository: dependencies.repository,
                photoStore: dependencies.photoStore,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(jpegData: jpegData)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteProgressPhoto() async {
        guard let progressPhoto else { return }
        do {
            try await DeleteProgressPhotoUseCase(
                repository: dependencies.repository,
                photoStore: dependencies.photoStore
            ).execute(id: progressPhoto.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveWorkout(_ draft: WorkoutDraft) async -> Bool {
        do {
            _ = try await SaveManualWorkoutUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(draft)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteWorkout(id: UUID) async {
        do {
            try await DeleteManualWorkoutUseCase(
                repository: dependencies.repository
            ).execute(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setManualCompletion(requirementID: String, isComplete: Bool) async {
        do {
            try await SetManualRequirementCompletionUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: ChallengeScheduler(calendar: dependencies.calendar)
            ).execute(requirementID: requirementID, isComplete: isComplete)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func correctIncompleteDayRequirement(_ requirementID: String) async {
        guard let review = incompleteDayReview else { return }
        do {
            let scheduler = ChallengeScheduler(calendar: dependencies.calendar)
            let calendar = scheduler.calendar(for: review.attempt)
            let startOfDay = try review.day.date(in: calendar)
            guard let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
                throw DomainError.invalidLocalDay
            }
            try await SetManualRequirementCompletionUseCase(
                repository: dependencies.repository,
                catalog: dependencies.catalog,
                scheduler: scheduler
            ).execute(requirementID: requirementID, isComplete: true, occurredAt: noon)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmFailureAndRestart() async {
        guard let review = incompleteDayReview,
              let restartDay = dashboard?.day,
              let program = dependencies.catalog.program(
                id: review.attempt.programID,
                version: review.attempt.programVersion
              )
        else { return }
        do {
            _ = try await RestartChallengeUseCase(
                repository: dependencies.repository,
                program: program,
                evaluator: RequirementEvaluator()
            ).execute(failedOn: review.day, restartOn: restartDay)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
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
