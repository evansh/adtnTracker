import Foundation
import Testing
@testable import _75Hard

struct GroupRepositoryTests {
    let repository: InMemoryGroupRepository

    init() {
        self.repository = InMemoryGroupRepository()
    }

    @Test func createAndFetchGroup() async throws {
        let group = AccountabilityGroup(
            id: UUID(),
            name: "Test Group",
            details: "A test group",
            visibility: .privateGroup,
            startDate: LocalDay(Date(), calendar: Calendar.current)
        )

        try await repository.save(group)
        let fetched = try await repository.group(id: group.id)

        #expect(fetched != nil)
        #expect(fetched?.name == "Test Group")
        #expect(fetched?.details == "A test group")
        #expect(fetched?.visibility == .privateGroup)
    }

    @Test func deleteGroup() async throws {
        let group = AccountabilityGroup(
            id: UUID(),
            name: "To Delete",
            details: "",
            visibility: .privateGroup,
            startDate: LocalDay(Date(), calendar: Calendar.current)
        )

        try await repository.save(group)
        try await repository.deleteGroup(id: group.id)
        let fetched = try await repository.group(id: group.id)

        #expect(fetched == nil)
    }

    @Test func membershipLifecycle() async throws {
        let userID = UUID()
        let groupID = UUID()

        let membership = GroupMembership(
            id: UUID(),
            groupID: groupID,
            userID: userID,
            role: .member
        )

        try await repository.saveMembership(membership)
        let fetched = try await repository.membership(groupID: groupID, userID: userID)

        #expect(fetched != nil)
        #expect(fetched?.role == .member)

        try await repository.deleteMembership(groupID: groupID, userID: userID)
        let afterDelete = try await repository.membership(groupID: groupID, userID: userID)
        #expect(afterDelete == nil)
    }

    @Test func groupInvites() async throws {
        let groupID = UUID()
        let createdBy = UUID()

        let invite = GroupInvite(
            groupID: groupID,
            createdBy: createdBy,
            expiresAt: nil,
            maxUses: 5
        )

        try await repository.saveInvite(invite)
        let fetched = try await repository.invite(code: invite.code)

        #expect(fetched != nil)
        #expect(fetched?.code == invite.code)
        #expect(fetched?.maxUses == 5)
        #expect(fetched?.uses == 0)
    }

    @Test func useInviteCreatesMembership() async throws {
        let groupID = UUID()
        let createdBy = UUID()
        let userID = UUID()

        let invite = GroupInvite(
            groupID: groupID,
            createdBy: createdBy,
            expiresAt: nil,
            maxUses: 1
        )
        try await repository.saveInvite(invite)

        let membership = try await repository.useInvite(code: invite.code, userID: userID)

        #expect(membership.groupID == groupID)
        #expect(membership.userID == userID)
        #expect(membership.role == .member)

        let inviteAfterUse = try await repository.invite(code: invite.code)
        #expect(inviteAfterUse?.uses == 1)
    }

    @Test func useInviteExpiredFails() async throws {
        let groupID = UUID()
        let createdBy = UUID()
        let userID = UUID()

        let invite = GroupInvite(
            groupID: groupID,
            createdBy: createdBy,
            expiresAt: Date().addingTimeInterval(-3600),
            maxUses: 1
        )
        try await repository.saveInvite(invite)

        await #expect(throws: DomainError.invalidEvidenceValue) {
            _ = try await repository.useInvite(code: invite.code, userID: userID)
        }
    }

    @Test func activitiesSavedAndFetched() async throws {
        let groupID = UUID()
        let userID = UUID()

        let activity = GroupActivity(
            groupID: groupID,
            userID: userID,
            userDisplayName: "Test User",
            type: .workoutCompleted,
            dayNumber: 5,
            workoutType: "Running",
            workoutDurationMinutes: 45
        )

        try await repository.saveActivity(activity)
        let activities = try await repository.activities(groupID: groupID, since: nil)

        #expect(activities.count == 1)
        #expect(activities[0].type == .workoutCompleted)
        #expect(activities[0].dayNumber == 5)
    }

    @Test func reactionsSavedAndFetched() async throws {
        let activityID = UUID()
        let userID = UUID()

        let reaction = GroupReaction(
            activityID: activityID,
            userID: userID,
            userDisplayName: "Test User",
            type: .fire
        )

        try await repository.saveReaction(reaction)
        let reactions = try await repository.reactions(activityID: activityID)

        #expect(reactions.count == 1)
        #expect(reactions[0].type == .fire)

        try await repository.deleteReaction(activityID: activityID, userID: userID)
        let afterDelete = try await repository.reactions(activityID: activityID)
        #expect(afterDelete.isEmpty)
    }
}

struct ExternalWorkoutServiceTests {
    let service: MockExternalWorkoutService

    init() {
        self.service = MockExternalWorkoutService()
    }

    @Test func availableSources() async throws {
        let sources = service.availableSources()
        #expect(sources.contains(.healthKit))
        #expect(sources.contains(.strava))
    }

    @Test func authorizationFlow() async throws {
        #expect(await service.isAuthorized(source: .healthKit) == false)

        try await service.requestAuthorization(source: .healthKit)

        #expect(await service.isAuthorized(source: .healthKit) == true)
    }

    @Test func fetchWorkoutsBeforeAuthReturnsEmpty() async throws {
        let workouts = try await service.fetchWorkouts(source: .healthKit, since: Date().addingTimeInterval(-86400))
        #expect(workouts.isEmpty)
    }

    @Test func fetchWorkoutsAfterAuthReturnsMockData() async throws {
        try await service.requestAuthorization(source: .healthKit)

        let workouts = try await service.fetchWorkouts(source: .healthKit, since: Date().addingTimeInterval(-86400))

        #expect(!workouts.isEmpty)
        #expect(workouts.allSatisfy { $0.source == .healthKit })
    }

    @Test func importWorkoutCreatesEvidenceRecord() async throws {
        try await service.requestAuthorization(source: .healthKit)

        let workouts = try await service.fetchWorkouts(source: .healthKit, since: Date().addingTimeInterval(-86400))
        let workout = try #require(workouts.first)

        let attemptID = UUID()
        let day = LocalDay(Date(), calendar: Calendar.current)

        let evidence = try await service.importWorkout(workout, asEvidenceFor: attemptID, on: day, slot: .first)

        #expect(evidence.attemptID == attemptID)
        #expect(evidence.occurredOn == day)
        #expect(evidence.source == .appleHealth)
        #expect(evidence.verification == .sourceVerified)
        #expect(evidence.externalID == workout.externalID)

        if case let .workout(workoutEvidence) = evidence.payload {
            #expect(workoutEvidence.type == workout.type)
            #expect(workoutEvidence.durationMinutes == workout.durationMinutes)
            #expect(workoutEvidence.isOutdoor == workout.isOutdoor)
            #expect(workoutEvidence.assignedSlot == .first)
        } else {
            Issue.record("Expected workout payload")
        }
    }

    @Test func suggestedWorkoutsForAuthorizedSources() async throws {
        try await service.requestAuthorization(source: .healthKit)
        try await service.requestAuthorization(source: .strava)

        let attemptID = UUID()
        let day = LocalDay(Date(), calendar: Calendar.current)

        let suggested = await service.suggestedWorkouts(for: attemptID, on: day)

        #expect(!suggested.isEmpty)
        let healthKitCount = suggested.filter { $0.source == .healthKit }.count
        let stravaCount = suggested.filter { $0.source == .strava }.count
        #expect(healthKitCount > 0)
        #expect(stravaCount > 0)
    }
}

struct SyncEngineTests {
    let engine: MockSyncEngine

    init() {
        self.engine = MockSyncEngine()
    }

    @Test func initialStatusIsNever() async throws {
        let status = await engine.status
        #expect(status.lastSyncedAt == nil)
        #expect(status.pendingChanges == 0)
        #expect(status.isSyncing == false)
        #expect(status.lastError == nil)
    }

    @Test func syncNowUpdatesStatus() async throws {
        try await engine.syncNow()
        let status = await engine.status

        #expect(status.lastSyncedAt != nil)
        #expect(status.isSyncing == false)
        #expect(status.lastError == nil)
    }
}

struct ModelsTests {
    @Test func externalWorkoutInitialization() {
        let workout = ExternalWorkout(
            source: .healthKit,
            externalID: "test-123",
            type: "Running",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            durationMinutes: 45,
            distanceMeters: 5000,
            isOutdoor: true
        )

        #expect(workout.source == .healthKit)
        #expect(workout.externalID == "test-123")
        #expect(workout.type == "Running")
        #expect(workout.durationMinutes == 45)
        #expect(workout.distanceMeters == 5000)
        #expect(workout.isOutdoor == true)
    }

    @Test func groupInviteCodeGeneration() {
        let invite = GroupInvite(
            groupID: UUID(),
            createdBy: UUID()
        )

        #expect(invite.code.count == 8)
        #expect(invite.code == invite.code.uppercased())
    }

    @Test func groupActivityTypes() {
        let activity = GroupActivity(
            groupID: UUID(),
            userID: UUID(),
            userDisplayName: "Test",
            type: .dayCompleted,
            dayNumber: 10
        )

        #expect(activity.type == .dayCompleted)
        #expect(activity.dayNumber == 10)
    }

    @Test func groupReactionTypes() {
        for type in GroupReactionType.allCases {
            let reaction = GroupReaction(
                activityID: UUID(),
                userID: UUID(),
                userDisplayName: "Test",
                type: type
            )
            #expect(reaction.type == type)
        }
    }

    @Test func syncStatusNever() {
        let status = SyncStatus.never
        #expect(status.lastSyncedAt == nil)
        #expect(status.pendingChanges == 0)
        #expect(status.isSyncing == false)
        #expect(status.lastError == nil)
    }
}