import Foundation

struct DependencyContainer: Sendable {
    let repository: any ChallengeRepository
    let photoStore: any ProgressPhotoStore
    let groupRepository: any GroupRepository
    let externalWorkoutService: any ExternalWorkoutService
    let syncEngine: any SyncEngine
    let catalog: any ProgramCatalog
    let calendar: Calendar

    static func live() throws -> DependencyContainer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return DependencyContainer(
            repository: try SecureFileChallengeRepository.live(),
            photoStore: try SecureProgressPhotoStore.live(),
            groupRepository: try SecureFileGroupRepository.live(),
            externalWorkoutService: MockExternalWorkoutService(),
            syncEngine: MockSyncEngine(),
            catalog: DefaultProgramCatalog(),
            calendar: calendar
        )
    }

    static func fallback() -> DependencyContainer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return DependencyContainer(
            repository: InMemoryChallengeRepository(),
            photoStore: InMemoryProgressPhotoStore(),
            groupRepository: InMemoryGroupRepository(),
            externalWorkoutService: MockExternalWorkoutService(),
            syncEngine: MockSyncEngine(),
            catalog: DefaultProgramCatalog(),
            calendar: calendar
        )
    }
}

actor InMemoryProgressPhotoStore: ProgressPhotoStore {
    private var photos: [UUID: Data] = [:]

    func saveJPEG(_ data: Data, id: UUID) async throws { photos[id] = data }
    func jpegData(id: UUID) async throws -> Data? { photos[id] }
    func delete(id: UUID) async throws { photos[id] = nil }
}

actor InMemoryChallengeRepository: ChallengeRepository {
    private var attempts: [ChallengeAttempt] = []
    private var records: [EvidenceRecord] = []

    func allAttempts() async throws -> [ChallengeAttempt] { attempts }
    func activeAttempt() async throws -> ChallengeAttempt? { attempts.last { $0.status == .active } }

    func save(_ attempt: ChallengeAttempt) async throws {
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
            attempts[index] = attempt
        } else {
            attempts.append(attempt)
        }
    }

    func evidence(attemptID: UUID, on day: LocalDay) async throws -> [EvidenceRecord] {
        records.filter { $0.attemptID == attemptID && $0.occurredOn == day }
    }

    func evidence(id: UUID) async throws -> EvidenceRecord? {
        records.first { $0.id == id }
    }

    func save(_ evidence: EvidenceRecord) async throws {
        if let index = records.firstIndex(where: { $0.id == evidence.id }) {
            records[index] = evidence
        } else {
            records.append(evidence)
        }
    }

    func deleteEvidence(id: UUID) async throws { records.removeAll { $0.id == id } }
}

actor InMemoryGroupRepository: GroupRepository {
    private var groups: [UUID: AccountabilityGroup] = [:]
    private var memberships: [UUID: [GroupMembership]] = [:] // userID -> memberships
    private var groupMemberships: [UUID: [GroupMembership]] = [:] // groupID -> memberships
    private var invites: [UUID: [GroupInvite]] = [:] // groupID -> invites
    private var activities: [UUID: [GroupActivity]] = [:] // groupID -> activities
    private var reactions: [UUID: [GroupReaction]] = [:] // activityID -> reactions
    private var inviteCodes: [String: GroupInvite] = [:] // code -> invite

    func allGroups() async throws -> [AccountabilityGroup] { Array(groups.values) }

    func group(id: UUID) async throws -> AccountabilityGroup? { groups[id] }

    func myGroups(userID: UUID) async throws -> [AccountabilityGroup] {
        let userMemberships = memberships[userID] ?? []
        return userMemberships.compactMap { groups[$0.groupID] }
    }

    func save(_ group: AccountabilityGroup) async throws {
        groups[group.id] = group
    }

    func deleteGroup(id: UUID) async throws {
        groups[id] = nil
        groupMemberships[id] = nil
        invites[id] = nil
        activities[id] = nil
    }

    func memberships(userID: UUID) async throws -> [GroupMembership] {
        memberships[userID] ?? []
    }

    func membership(groupID: UUID, userID: UUID) async throws -> GroupMembership? {
        groupMemberships[groupID]?.first { $0.userID == userID }
    }

    func saveMembership(_ membership: GroupMembership) async throws {
        if memberships[membership.userID] == nil { memberships[membership.userID] = [] }
        if groupMemberships[membership.groupID] == nil { groupMemberships[membership.groupID] = [] }

        memberships[membership.userID]?.removeAll { $0.id == membership.id }
        memberships[membership.userID]?.append(membership)

        groupMemberships[membership.groupID]?.removeAll { $0.id == membership.id }
        groupMemberships[membership.groupID]?.append(membership)
    }

    func deleteMembership(groupID: UUID, userID: UUID) async throws {
        memberships[userID]?.removeAll { $0.groupID == groupID }
        groupMemberships[groupID]?.removeAll { $0.userID == userID }
    }

    func members(groupID: UUID) async throws -> [GroupMembership] {
        groupMemberships[groupID] ?? []
    }

    func invites(groupID: UUID) async throws -> [GroupInvite] {
        invites[groupID] ?? []
    }

    func invite(code: String) async throws -> GroupInvite? {
        inviteCodes[code.uppercased()]
    }

    func saveInvite(_ invite: GroupInvite) async throws {
        if invites[invite.groupID] == nil { invites[invite.groupID] = [] }
        invites[invite.groupID]?.removeAll { $0.id == invite.id }
        invites[invite.groupID]?.append(invite)
        inviteCodes[invite.code.uppercased()] = invite
    }

    func useInvite(code: String, userID: UUID) async throws -> GroupMembership {
        guard let invite = inviteCodes[code.uppercased()] else {
            throw DomainError.invalidEvidenceValue
        }
        if let maxUses = invite.maxUses, invite.uses >= maxUses {
            throw DomainError.invalidEvidenceValue
        }
        if let expiresAt = invite.expiresAt, expiresAt < Date() {
            throw DomainError.invalidEvidenceValue
        }

        var updatedInvite = invite
        updatedInvite.uses += 1
        try await saveInvite(updatedInvite)

        let membership = GroupMembership(
            id: UUID(),
            groupID: invite.groupID,
            userID: userID,
            role: .member
        )
        try await saveMembership(membership)
        return membership
    }

    func activities(groupID: UUID, since: Date?) async throws -> [GroupActivity] {
        let all = activities[groupID] ?? []
        if let since = since {
            return all.filter { $0.createdAt > since }.sorted { $0.createdAt > $1.createdAt }
        }
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    func saveActivity(_ activity: GroupActivity) async throws {
        if activities[activity.groupID] == nil { activities[activity.groupID] = [] }
        activities[activity.groupID]?.removeAll { $0.id == activity.id }
        activities[activity.groupID]?.append(activity)
    }

    func reactions(activityID: UUID) async throws -> [GroupReaction] {
        reactions[activityID] ?? []
    }

    func saveReaction(_ reaction: GroupReaction) async throws {
        if reactions[reaction.activityID] == nil { reactions[reaction.activityID] = [] }
        reactions[reaction.activityID]?.removeAll { $0.id == reaction.id }
        reactions[reaction.activityID]?.append(reaction)
    }

    func deleteReaction(activityID: UUID, userID: UUID) async throws {
        reactions[activityID]?.removeAll { $0.userID == userID }
    }
}

actor MockExternalWorkoutService: ExternalWorkoutService {
    private var authorizedSources: Set<ExternalWorkoutSource> = []
    private var mockWorkouts: [ExternalWorkoutSource: [ExternalWorkout]] = [
        .healthKit: [
            ExternalWorkout(
                source: .healthKit,
                externalID: "hk-1",
                type: "Running",
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date(),
                durationMinutes: 45,
                distanceMeters: 5000,
                isOutdoor: true,
                routeCoordinates: [[37.7749, -122.4194], [37.7849, -122.4094]],
                elevationGainMeters: 50
            ),
            ExternalWorkout(
                source: .healthKit,
                externalID: "hk-2",
                type: "Cycling",
                startDate: Date().addingTimeInterval(-7200),
                endDate: Date().addingTimeInterval(-3600),
                durationMinutes: 60,
                distanceMeters: 20000,
                isOutdoor: true
            )
        ],
        .strava: [
            ExternalWorkout(
                source: .strava,
                externalID: "strava-1",
                type: "Run",
                startDate: Date().addingTimeInterval(-10800),
                endDate: Date().addingTimeInterval(-7200),
                durationMinutes: 50,
                distanceMeters: 8000,
                isOutdoor: true,
                routeCoordinates: [[37.7749, -122.4194], [37.7849, -122.4094], [37.7949, -122.3994]],
                elevationGainMeters: 120
            )
        ]
    ]

    func availableSources() -> [ExternalWorkoutSource] { [.healthKit, .strava] }

    func requestAuthorization(source: ExternalWorkoutSource) async throws {
        authorizedSources.insert(source)
    }

    func isAuthorized(source: ExternalWorkoutSource) async -> Bool {
        authorizedSources.contains(source)
    }

    func fetchWorkouts(source: ExternalWorkoutSource, since: Date) async throws -> [ExternalWorkout] {
        guard authorizedSources.contains(source) else { return [] }
        return mockWorkouts[source]?.filter { $0.startDate > since } ?? []
    }

    func importWorkout(_ workout: ExternalWorkout, asEvidenceFor attemptID: UUID, on day: LocalDay, slot: WorkoutSlot) async throws -> EvidenceRecord {
        let evidence = EvidenceRecord(
            attemptID: attemptID,
            occurredOn: day,
            occurredAt: workout.startDate,
            source: workout.source == .healthKit ? .appleHealth : .strava,
            verification: .sourceVerified,
            externalID: workout.externalID,
            payload: .workout(WorkoutEvidence(
                type: workout.type,
                durationMinutes: workout.durationMinutes,
                isOutdoor: workout.isOutdoor,
                distanceMeters: workout.distanceMeters,
                assignedSlot: slot,
                notes: "Imported from \(workout.source.rawValue.capitalized)"
            ))
        )
        return evidence
    }

    func suggestedWorkouts(for attemptID: UUID, on day: LocalDay) async -> [ExternalWorkout] {
        var all: [ExternalWorkout] = []
        for source in authorizedSources {
            all.append(contentsOf: mockWorkouts[source] ?? [])
        }
        return all
    }
}

actor MockSyncEngine: SyncEngine {
    private var _status = SyncStatus.never

    var status: SyncStatus {
        get async { _status }
    }

    func syncNow() async throws {
        _status = SyncStatus(lastSyncedAt: nil, pendingChanges: 0, isSyncing: true, lastError: nil)
        try await Task.sleep(nanoseconds: 500_000_000)
        _status = SyncStatus(lastSyncedAt: .now, pendingChanges: 0, isSyncing: false, lastError: nil)
    }

    func registerForBackgroundSync() {
        // Mock: no-op
    }
}
