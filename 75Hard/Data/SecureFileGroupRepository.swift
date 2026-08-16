import Foundation

actor SecureFileGroupRepository: GroupRepository {
    private struct PersistedState: Codable {
        var groups: [AccountabilityGroup] = []
        var memberships: [GroupMembership] = []
        var invites: [GroupInvite] = []
        var activities: [GroupActivity] = []
        var reactions: [GroupReaction] = []
    }

    private let fileURL: URL
    private var cachedState: PersistedState?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func live() throws -> SecureFileGroupRepository {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return SecureFileGroupRepository(
            fileURL: root.appending(path: "75Hard", directoryHint: .isDirectory)
                .appending(path: "group-state.json", directoryHint: .notDirectory)
        )
    }

    func allGroups() async throws -> [AccountabilityGroup] {
        try load().groups
    }

    func group(id: UUID) async throws -> AccountabilityGroup? {
        try load().groups.first { $0.id == id }
    }

    func myGroups(userID: UUID) async throws -> [AccountabilityGroup] {
        let state = try load()
        let userGroupIDs = Set(state.memberships.filter { $0.userID == userID }.map { $0.groupID })
        return state.groups.filter { userGroupIDs.contains($0.id) }
    }

    func save(_ group: AccountabilityGroup) async throws {
        var state = try load()
        if let index = state.groups.firstIndex(where: { $0.id == group.id }) {
            state.groups[index] = group
        } else {
            state.groups.append(group)
        }
        try persist(state)
    }

    func deleteGroup(id: UUID) async throws {
        var state = try load()
        state.groups.removeAll { $0.id == id }
        state.memberships.removeAll { $0.groupID == id }
        state.invites.removeAll { $0.groupID == id }
        state.activities.removeAll { $0.groupID == id }
        try persist(state)
    }

    func memberships(userID: UUID) async throws -> [GroupMembership] {
        try load().memberships.filter { $0.userID == userID }
    }

    func membership(groupID: UUID, userID: UUID) async throws -> GroupMembership? {
        try load().memberships.first { $0.groupID == groupID && $0.userID == userID }
    }

    func saveMembership(_ membership: GroupMembership) async throws {
        var state = try load()
        if let index = state.memberships.firstIndex(where: { $0.id == membership.id }) {
            state.memberships[index] = membership
        } else {
            state.memberships.append(membership)
        }
        try persist(state)
    }

    func deleteMembership(groupID: UUID, userID: UUID) async throws {
        var state = try load()
        state.memberships.removeAll { $0.groupID == groupID && $0.userID == userID }
        try persist(state)
    }

    func members(groupID: UUID) async throws -> [GroupMembership] {
        try load().memberships.filter { $0.groupID == groupID }
    }

    func invites(groupID: UUID) async throws -> [GroupInvite] {
        try load().invites.filter { $0.groupID == groupID }
    }

    func invite(code: String) async throws -> GroupInvite? {
        try load().invites.first { $0.code.uppercased() == code.uppercased() }
    }

    func saveInvite(_ invite: GroupInvite) async throws {
        var state = try load()
        if let index = state.invites.firstIndex(where: { $0.id == invite.id }) {
            state.invites[index] = invite
        } else {
            state.invites.append(invite)
        }
        try persist(state)
    }

    func useInvite(code: String, userID: UUID) async throws -> GroupMembership {
        var state = try load()
        guard let inviteIndex = state.invites.firstIndex(where: { $0.code.uppercased() == code.uppercased() }) else {
            throw DomainError.invalidEvidenceValue
        }
        var invite = state.invites[inviteIndex]
        if let maxUses = invite.maxUses, invite.uses >= maxUses {
            throw DomainError.invalidEvidenceValue
        }
        if let expiresAt = invite.expiresAt, expiresAt < Date() {
            throw DomainError.invalidEvidenceValue
        }

        invite.uses += 1
        state.invites[inviteIndex] = invite

        let membership = GroupMembership(
            id: UUID(),
            groupID: invite.groupID,
            userID: userID,
            role: .member
        )
        state.memberships.append(membership)

        try persist(state)
        return membership
    }

    func activities(groupID: UUID, since: Date?) async throws -> [GroupActivity] {
        let state = try load()
        var result = state.activities.filter { $0.groupID == groupID }
        if let since = since {
            result = result.filter { $0.createdAt > since }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func saveActivity(_ activity: GroupActivity) async throws {
        var state = try load()
        if let index = state.activities.firstIndex(where: { $0.id == activity.id }) {
            state.activities[index] = activity
        } else {
            state.activities.append(activity)
        }
        try persist(state)
    }

    func reactions(activityID: UUID) async throws -> [GroupReaction] {
        try load().reactions.filter { $0.activityID == activityID }
    }

    func saveReaction(_ reaction: GroupReaction) async throws {
        var state = try load()
        if let index = state.reactions.firstIndex(where: { $0.id == reaction.id }) {
            state.reactions[index] = reaction
        } else {
            state.reactions.append(reaction)
        }
        try persist(state)
    }

    func deleteReaction(activityID: UUID, userID: UUID) async throws {
        var state = try load()
        state.reactions.removeAll { $0.activityID == activityID && $0.userID == userID }
        try persist(state)
    }

    private func load() throws -> PersistedState {
        if let cachedState { return cachedState }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let empty = PersistedState()
            cachedState = empty
            return empty
        }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let state = try JSONDecoder.securePersistence.decode(PersistedState.self, from: data)
            cachedState = state
            return state
        } catch {
            throw DomainError.persistenceFailure
        }
    }

    private func persist(_ state: PersistedState) throws {
        do {
            let fileManager = FileManager.default
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)

            let data = try JSONEncoder.securePersistence.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            cachedState = state
        } catch {
            throw DomainError.persistenceFailure
        }
    }
}