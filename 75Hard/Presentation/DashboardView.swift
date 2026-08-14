import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List {
            if snapshot.evaluation.isComplete {
                Section {
                    Label("Day complete", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .accessibilityLabel("All requirements are complete for today")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayTitle)
                        .font(.largeTitle.bold())
                    ProgressView(value: snapshot.timing.completionPercentage, total: 100)
                        .accessibilityLabel("Challenge progress")
                        .accessibilityValue("\(Int(snapshot.timing.completionPercentage)) percent")
                    Text("\(snapshot.evaluation.completedCount) of \(snapshot.evaluation.requirements.count) complete today")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Today's requirements") {
                ForEach(snapshot.evaluation.requirements) { requirement in
                    if isWorkoutRequirement(requirement.id) {
                        NavigationLink {
                            WorkoutListView(viewModel: viewModel)
                        } label: {
                            RequirementRow(requirement: requirement)
                        }
                    } else {
                        RequirementRow(requirement: requirement)
                    }
                }
            }

            Section("Quick add water") {
                HStack {
                    ForEach([8, 12, 16, 24], id: \.self) { ounces in
                        Button("\(ounces) oz") {
                            Task { await viewModel.addWater(ounces: ounces) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .navigationTitle("Today")
        .refreshable { await viewModel.load() }
    }

    private var dayTitle: String {
        guard let day = snapshot.timing.dayNumber else {
            return snapshot.timing.phase == .upcoming ? "Starts soon" : "Challenge ended"
        }
        return "Day \(day) of \(snapshot.program.durationDays)"
    }

    private func isWorkoutRequirement(_ id: String) -> Bool {
        id == WorkoutSlot.first.rawValue ||
            id == WorkoutSlot.second.rawValue ||
            id == "outdoor-workout"
    }
}

private struct RequirementRow: View {
    let requirement: RequirementEvaluation

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(requirement.title)
                if let current = requirement.currentValue,
                   let target = requirement.targetValue,
                   target > 1 {
                    Text("\(min(current, target)) / \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch requirement.status {
        case .complete: "checkmark.circle.fill"
        case .automaticallyVerified: "checkmark.seal.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .notComplete: "circle"
        }
    }

    private var color: Color {
        requirement.status.isSatisfied ? .green : (requirement.status == .inProgress ? .orange : .secondary)
    }

    private var statusLabel: String {
        switch requirement.status {
        case .complete: "Complete"
        case .automaticallyVerified: "Verified"
        case .inProgress: "In progress"
        case .notComplete: "Not complete"
        }
    }
}

private struct WorkoutListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedWorkout: RecordedWorkout?
    @State private var pendingDeletion: RecordedWorkout?
    @State private var defaultSlot: WorkoutSlot = .first
    @State private var isShowingEditor = false

    var body: some View {
        List {
            Section {
                Text("Record each workout separately. A workout must be at least 45 minutes to satisfy its assigned slot.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(WorkoutSlot.allCases, id: \.self) { slot in
                Section(slot.displayName) {
                    if let workout = workout(for: slot) {
                        workoutContent(workout)
                    } else {
                        Button {
                            presentEditor(workout: nil, slot: slot)
                        } label: {
                            Label("Record \(slot.displayName)", systemImage: "plus.circle")
                        }
                    }
                }
            }

            let unassigned = viewModel.workouts.filter { $0.workout.assignedSlot == nil }
            if !unassigned.isEmpty {
                Section("Unassigned imported workouts") {
                    ForEach(unassigned) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let slot = nextAvailableSlot else { return }
                    presentEditor(workout: nil, slot: slot)
                } label: {
                    Label("Record workout", systemImage: "plus")
                }
                .disabled(nextAvailableSlot == nil)
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                WorkoutEditorView(
                    viewModel: viewModel,
                    workout: selectedWorkout,
                    defaultSlot: defaultSlot
                )
            }
        }
        .confirmationDialog(
            "Delete workout?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive) {
                guard let workout = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await viewModel.deleteWorkout(id: workout.id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the workout from today's evidence and recalculates completion.")
        }
    }

    @ViewBuilder
    private func workoutContent(_ workout: RecordedWorkout) -> some View {
        if workout.canEdit {
            Button {
                presentEditor(workout: workout, slot: workout.workout.assignedSlot ?? .first)
            } label: {
                WorkoutRow(workout: workout)
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Delete", role: .destructive) {
                    pendingDeletion = workout
                }
            }
        } else {
            WorkoutRow(workout: workout)
        }
    }

    private var nextAvailableSlot: WorkoutSlot? {
        WorkoutSlot.allCases.first { workout(for: $0) == nil }
    }

    private func workout(for slot: WorkoutSlot) -> RecordedWorkout? {
        viewModel.workouts.first { $0.workout.assignedSlot == slot }
    }

    private func presentEditor(workout: RecordedWorkout?, slot: WorkoutSlot) {
        selectedWorkout = workout
        defaultSlot = slot
        isShowingEditor = true
    }
}

private struct WorkoutRow: View {
    let workout: RecordedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workout.workout.type)
                    .font(.headline)
                Spacer()
                if workout.workout.isOutdoor {
                    Label("Outdoor", systemImage: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let notes = workout.workout.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(sourceLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var components = [
            workout.occurredAt.formatted(date: .omitted, time: .shortened),
            "\(workout.workout.durationMinutes) min",
        ]
        if let distance = workout.workout.distanceMeters {
            let miles = Measurement(value: distance, unit: UnitLength.meters)
                .converted(to: .miles)
                .value
            components.append(miles.formatted(.number.precision(.fractionLength(1))) + " mi")
        }
        return components.joined(separator: " • ")
    }

    private var sourceLabel: String {
        switch workout.source {
        case .manual: "Manual entry"
        case .camera: "Camera"
        case .appleHealth: "Apple Health"
        case .strava: "Strava"
        }
    }
}

private struct WorkoutEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    let workout: RecordedWorkout?

    @Environment(\.dismiss) private var dismiss
    @State private var slot: WorkoutSlot
    @State private var type: String
    @State private var startedAt: Date
    @State private var durationMinutes: Int
    @State private var isOutdoor: Bool
    @State private var distanceMiles: String
    @State private var notes: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(viewModel: AppViewModel, workout: RecordedWorkout?, defaultSlot: WorkoutSlot) {
        self.viewModel = viewModel
        self.workout = workout
        _slot = State(initialValue: workout?.workout.assignedSlot ?? defaultSlot)
        _type = State(initialValue: workout?.workout.type ?? "")
        _startedAt = State(initialValue: workout?.occurredAt ?? .now)
        _durationMinutes = State(initialValue: workout?.workout.durationMinutes ?? 45)
        _isOutdoor = State(initialValue: workout?.workout.isOutdoor ?? false)
        if let meters = workout?.workout.distanceMeters {
            let miles = Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles).value
            _distanceMiles = State(initialValue: miles.formatted(.number.precision(.fractionLength(0...2))))
        } else {
            _distanceMiles = State(initialValue: "")
        }
        _notes = State(initialValue: workout?.workout.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Assignment") {
                Picker("Requirement", selection: $slot) {
                    ForEach(WorkoutSlot.allCases, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
            }

            Section("Workout") {
                TextField("Activity type", text: $type)
                    .textInputAutocapitalization(.words)
                DatePicker("Start time", selection: $startedAt, displayedComponents: .hourAndMinute)
                Stepper("Duration: \(durationMinutes) minutes", value: $durationMinutes, in: 1...1_440)
                Toggle("Outdoor workout", isOn: $isOutdoor)
                TextField("Distance in miles (optional)", text: $distanceMiles)
                    .keyboardType(.decimalPad)
            }

            Section("Notes (optional)") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .onChange(of: notes) { _, newValue in
                        if newValue.count > 500 {
                            notes = String(newValue.prefix(500))
                        }
                    }
                Text("\(notes.count) / 500")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Validation error: \(validationMessage)")
                }
            }
        }
        .navigationTitle(workout == nil ? "Record Workout" : "Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving || type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor
    private func save() async {
        validationMessage = nil
        let normalizedDistance = distanceMiles
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let distanceMeters: Double?
        if normalizedDistance.isEmpty {
            distanceMeters = nil
        } else if let miles = Double(normalizedDistance), miles.isFinite, miles >= 0 {
            distanceMeters = Measurement(value: miles, unit: UnitLength.miles)
                .converted(to: .meters)
                .value
        } else {
            validationMessage = "Enter a valid non-negative distance."
            return
        }

        isSaving = true
        let didSave = await viewModel.saveWorkout(WorkoutDraft(
            id: workout?.id,
            slot: slot,
            type: type,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            isOutdoor: isOutdoor,
            distanceMeters: distanceMeters,
            notes: notes
        ))
        isSaving = false
        if didSave { dismiss() }
    }
}

private extension WorkoutSlot {
    var displayName: String {
        switch self {
        case .first: "Workout #1"
        case .second: "Workout #2"
        }
    }
}
