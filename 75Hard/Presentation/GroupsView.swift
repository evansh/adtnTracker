import SwiftUI

struct GroupsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var joinCode = ""
    @State private var showingInviteCode = false
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            List {
                if viewModel.myGroups.isEmpty {
                    emptyState
                } else {
                    myGroupsSection
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create Group", systemImage: "plus") {
                            showingCreateGroup = true
                        }
                        Button("Join Group", systemImage: "person.badge.plus") {
                            showingJoinGroup = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingInviteCode) {
                if let group = viewModel.selectedGroup {
                    InviteCodeView(group: group, code: inviteCode, viewModel: viewModel)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No groups yet")
                .font(.title2.bold())
            Text("Create a group or join one with an invite code to share your progress with friends.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            VStack(spacing: 12) {
                Button("Create Group", systemImage: "plus") {
                    showingCreateGroup = true
                }
                .buttonStyle(.borderedProminent)
                Button("Join Group", systemImage: "person.badge.plus") {
                    showingJoinGroup = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowBackground(Color.clear)
    }

    private var myGroupsSection: some View {
        Section("My Groups") {
            ForEach(viewModel.myGroups) { group in
                GroupRow(
                    group: group,
                    isSelected: viewModel.selectedGroup?.id == group.id,
                    onTap: {
                        Task { await viewModel.selectGroup(group) }
                    },
                    onInvite: {
                        Task {
                            if let code = await viewModel.createInviteCode(for: group.id) {
                                inviteCode = code
                                showingInviteCode = true
                            }
                        }
                    },
                    onLeave: {
                        Task { await viewModel.leaveGroup(group.id) }
                    }
                )
            }
        }
    }
}

struct GroupRow: View {
    let group: AccountabilityGroup
    let isSelected: Bool
    let onTap: () -> Void
    let onInvite: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                    Text(group.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: group.visibility == .publicGroup ? "globe" : "lock")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Day \(group.startDate.day)", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Button("View", systemImage: "eye") {
                    onTap()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Invite", systemImage: "person.badge.plus") {
                    onInvite()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if group.visibility == .privateGroup {
                    Button("Leave", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                        onLeave()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct CreateGroupView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var visibility: GroupVisibility = .privateGroup
    @State private var startDate = LocalDay(Date(), calendar: Calendar.current)

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Group Name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Privacy", selection: $visibility) {
                        Text("Private").tag(GroupVisibility.privateGroup)
                        Text("Public").tag(GroupVisibility.publicGroup)
                    }
                }

                Section("Start Date") {
                    DatePicker("Challenge Start", selection: Binding(
                        get: { startDate.date(in: Calendar.current) ?? Date() },
                        set: { startDate = LocalDay($0, calendar: Calendar.current) }
                    ), displayedComponents: .date)
                }

                Section {
                    Button("Create Group") {
                        Task {
                            await viewModel.createGroup(
                                name: name,
                                details: details,
                                visibility: visibility,
                                startDate: startDate
                            )
                            if viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Create Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct JoinGroupView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Enter Invite Code") {
                    TextField("ABC123XY", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Join Group") {
                        Task {
                            await viewModel.joinGroupWithCode(code.uppercased())
                            if viewModel.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(code.count < 6)
                }
            }
            .navigationTitle("Join Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct InviteCodeView: View {
    let group: AccountabilityGroup
    let code: String
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "qrcode")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text(group.name)
                    .font(.title.bold())

                Text("Invite Code")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Copy Code") {
                    UIPasteboard.general.string = code
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Share Invite")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}