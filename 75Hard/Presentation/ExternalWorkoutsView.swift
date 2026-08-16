import SwiftUI

struct ExternalWorkoutsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showingImportSheet = false
    @State private var workoutToImport: ExternalWorkout?
    @State private var importSlot: WorkoutSlot = .first

    var body: some View {
        NavigationStack {
            List {
                authorizationSection
                availableWorkoutsSection
                syncSection
            }
            .navigationTitle("Integrations")
            .task {
                await viewModel.loadExternalWorkoutSources()
            }
            .refreshable {
                await viewModel.loadExternalWorkoutSources()
                await viewModel.loadAvailableExternalWorkouts()
                await viewModel.loadSyncStatus()
            }
            .sheet(item: $workoutToImport) { workout in
                ImportWorkoutView(
                    workout: workout,
                    slot: $importSlot,
                    onImport: { selectedSlot in
                        Task {
                            await viewModel.importExternalWorkout(workout, slot: selectedSlot)
                            workoutToImport = nil
                        }
                    }
                )
            }
        }
    }

    private var authorizationSection: some View {
        Section("Authorization") {
            ForEach(viewModel.externalWorkoutSources, id: \.self) { source in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceDisplayName(source))
                            .font(.headline)
                        Text(sourceDescription(source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.authorizedSources.contains(source) {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Button("Connect") {
                            Task { await viewModel.authorizeExternalSource(source) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var availableWorkoutsSection: some View {
        Section("Available Workouts") {
            if viewModel.availableExternalWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No workouts available")
                        .font(.headline)
                    Text("Connect HealthKit or Strava to see imported workouts, or pull to refresh.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.availableExternalWorkouts) { workout in
                    ExternalWorkoutRow(
                        workout: workout,
                        onImport: {
                            workoutToImport = workout
                        }
                    )
                }
            }
        }
    }

    private var syncSection: some View {
        Section("Sync") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background Sync")
                        .font(.headline)
                    Text("Automatically sync group data when online")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.syncStatus.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(lastSyncText, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await viewModel.triggerSync() }
            } label: {
                HStack {
                    if viewModel.syncStatus.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing…")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Sync Now")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.syncStatus.isSyncing)

            if let error = viewModel.syncStatus.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func sourceDisplayName(_ source: ExternalWorkoutSource) -> String {
        switch source {
        case .healthKit: return "Apple Health"
        case .strava: return "Strava"
        }
    }

    private func sourceDescription(_ source: ExternalWorkoutSource) -> String {
        switch source {
        case .healthKit: return "Import workouts from the Health app"
        case .strava: return "Import activities from Strava"
        }
    }

    private var lastSyncText: String {
        if let lastSynced = viewModel.syncStatus.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: lastSynced, relativeTo: Date()))"
        }
        return "Never synced"
    }
}

struct ExternalWorkoutRow: View {
    let workout: ExternalWorkout
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.type)
                        .font(.headline)
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import", systemImage: "square.and.arrow.down") {
                    onImport()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 16) {
                Label("\(workout.durationMinutes) min", systemImage: "clock")
                if let distance = workout.distanceMeters {
                    Label(formatDistance(distance), systemImage: "location")
                }
                if workout.isOutdoor {
                    Label("Outdoor", systemImage: "leaf.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(workout.startDate, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var sourceLabel: String {
        switch workout.source {
        case .healthKit: return "Apple Health"
        case .strava: return "Strava"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

struct ImportWorkoutView: View {
    let workout: ExternalWorkout
    @Binding var slot: WorkoutSlot
    let onImport: (WorkoutSlot) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Details") {
                    LabeledContent("Type", value: workout.type)
                    LabeledContent("Duration", value: "\(workout.durationMinutes) min")
                    if let distance = workout.distanceMeters {
                        LabeledContent("Distance", value: formatDistance(distance))
                    }
                    LabeledContent("Location", value: workout.isOutdoor ? "Outdoor" : "Indoor")
                    LabeledContent("Source", value: sourceLabel(for: workout))
                }

                Section("Assign to Slot") {
                    Picker("Workout Slot", selection: $slot) {
                        ForEach(WorkoutSlot.allCases) { s in
                            Text(slotDisplayName(s)).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Import as \(slotDisplayName(slot))") {
                        onImport(slot)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Import Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private func sourceLabel(for workout: ExternalWorkout) -> String {
    switch workout.source {
    case .healthKit: return "Apple Health"
    case .strava: return "Strava"
    }
}

private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.1f km", meters / 1000)
    }
    return "\(Int(meters)) m"
}

private func slotDisplayName(_ slot: WorkoutSlot) -> String {
    slot == .first ? "Workout #1" : "Workout #2"
}