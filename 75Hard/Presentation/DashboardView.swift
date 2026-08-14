import PhotosUI
import SwiftUI
import UIKit

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingFailureConfirmation = false

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

            if let review = viewModel.incompleteDayReview {
                Section("Day \(review.dayNumber) needs review") {
                    Text("Correct anything recorded incorrectly, or confirm that the challenge should restart.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(review.unmetRequirements) { requirement in
                        Button {
                            Task {
                                await viewModel.correctIncompleteDayRequirement(requirement.id)
                            }
                        } label: {
                            Label("Mark \(requirement.title) complete", systemImage: "square")
                        }
                    }
                    Button("Confirm failure and restart", role: .destructive) {
                        isShowingFailureConfirmation = true
                    }
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
                    HStack(spacing: 10) {
                        if isWorkoutRequirement(requirement.id) {
                            NavigationLink {
                                WorkoutListView(viewModel: viewModel)
                            } label: {
                                RequirementRow(requirement: requirement)
                            }
                        } else if requirement.id == "water" {
                            NavigationLink {
                                HydrationView(requirement: requirement, viewModel: viewModel)
                            } label: {
                                RequirementRow(requirement: requirement)
                            }
                        } else if requirement.id == "diet" {
                            NavigationLink {
                                DietView(viewModel: viewModel)
                            } label: {
                                RequirementRow(requirement: requirement)
                            }
                        } else if requirement.id == "reading" {
                            NavigationLink {
                                ReadingView(requirement: requirement, viewModel: viewModel)
                            } label: {
                                RequirementRow(requirement: requirement)
                            }
                        } else if requirement.id == "progress-photo" {
                            NavigationLink {
                                ProgressPhotoView(viewModel: viewModel)
                            } label: {
                                RequirementRow(requirement: requirement)
                            }
                        } else {
                            RequirementRow(requirement: requirement)
                        }

                        Button {
                            Task {
                                await viewModel.setManualCompletion(
                                    requirementID: requirement.id,
                                    isComplete: !requirement.isManuallyCompleted
                                )
                            }
                        } label: {
                            Image(systemName: requirement.status.isSatisfied ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(requirement.status.isSatisfied ? .green : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(requirement.status.isSatisfied && !requirement.isManuallyCompleted)
                        .accessibilityLabel(requirement.isManuallyCompleted
                            ? "Remove manual completion for \(requirement.title)"
                            : "Mark \(requirement.title) complete manually")
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
        .confirmationDialog(
            "Restart at Day 1?",
            isPresented: $isShowingFailureConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm and restart", role: .destructive) {
                Task { await viewModel.confirmFailureAndRestart() }
            }
            Button("Keep correcting", role: .cancel) {}
        } message: {
            Text("The previous attempt and its evidence will be preserved. You can keep correcting entries instead if the detected failure is inaccurate.")
        }
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

private struct HydrationView: View {
    let requirement: RequirementEvaluation
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedEntry: RecordedHydration?
    @State private var isShowingEditor = false
    @State private var pendingDeletion: RecordedHydration?

    var body: some View {
        List {
            Section("Today's progress") {
                Text(progressText)
                    .font(.title2.bold())
                ProgressView(
                    value: Double(currentRequirement.currentValue ?? 0),
                    total: Double(currentRequirement.targetValue ?? 1)
                )
                .accessibilityLabel("Water progress")
                .accessibilityValue(progressText)
            }

            Section("Quick add") {
                HStack {
                    ForEach([8, 12, 16, 24], id: \.self) { ounces in
                        Button("\(ounces) oz") {
                            Task { await viewModel.addWater(ounces: ounces) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Button {
                    selectedEntry = nil
                    isShowingEditor = true
                } label: {
                    Label("Add custom amount", systemImage: "plus.circle")
                }
            }

            Section("Entries") {
                if viewModel.hydrationEntries.isEmpty {
                    ContentUnavailableView(
                        "No water entries",
                        systemImage: "drop",
                        description: Text("Use a quick amount or add a custom entry.")
                    )
                } else {
                    ForEach(viewModel.hydrationEntries) { entry in
                        Button {
                            guard entry.canEdit else { return }
                            selectedEntry = entry
                            isShowingEditor = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(ounces(for: entry.milliliters) + " oz")
                                        .font(.headline)
                                    Text(entry.occurredAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entry.source != .manual {
                                    Text("Imported")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if entry.canEdit {
                                Button("Delete", role: .destructive) {
                                    pendingDeletion = entry
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Water")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedEntry = nil
                    isShowingEditor = true
                } label: {
                    Label("Add water", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                HydrationEditorView(viewModel: viewModel, entry: selectedEntry)
            }
        }
        .confirmationDialog(
            "Delete water entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete entry", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await viewModel.deleteHydration(id: entry.id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Today's water progress will be recalculated.")
        }
    }

    private var progressText: String {
        "\(ounces(for: currentRequirement.currentValue ?? 0)) / \(ounces(for: currentRequirement.targetValue ?? 0)) oz"
    }

    private var currentRequirement: RequirementEvaluation {
        viewModel.dashboard?.evaluation.requirements.first { $0.id == requirement.id } ?? requirement
    }

    private func ounces(for milliliters: Int) -> String {
        (Double(milliliters) / 29.5735)
            .formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct HydrationEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    let entry: RecordedHydration?

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(viewModel: AppViewModel, entry: RecordedHydration?) {
        self.viewModel = viewModel
        self.entry = entry
        if let entry {
            _amount = State(initialValue: (Double(entry.milliliters) / 29.5735)
                .formatted(.number.precision(.fractionLength(0...1))))
        } else {
            _amount = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section("Amount") {
                TextField("Fluid ounces", text: $amount)
                    .keyboardType(.decimalPad)
                Text("Amounts are stored in milliliters so future clients can display the user's preferred unit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(entry == nil ? "Add Water" : "Edit Water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor
    private func save() async {
        let normalized = amount
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let ounces = Double(normalized), ounces.isFinite, ounces > 0 else {
            validationMessage = "Enter a valid amount greater than zero."
            return
        }
        let milliliters = Int((ounces * 29.5735).rounded())
        guard (1...5_000).contains(milliliters) else {
            validationMessage = "Enter an amount no greater than 169 fluid ounces."
            return
        }
        isSaving = true
        let didSave = await viewModel.saveHydration(id: entry?.id, milliliters: milliliters)
        isSaving = false
        if didSave { dismiss() }
    }
}

private struct DietView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingPlanEditor = false
    @State private var isShowingCheckEditor = false
    @State private var proposedCompliance = true

    var body: some View {
        List {
            if let plan {
                Section("Your diet") {
                    Text(plan.name)
                        .font(.headline)
                    Text(plan.rules)
                        .foregroundStyle(.secondary)
                    Button("Edit diet definition") {
                        isShowingPlanEditor = true
                    }
                }

                Section("Today's compliance") {
                    if let compliance = viewModel.dietCompliance {
                        Label(
                            compliance.isCompliant ? "Marked compliant" : "Marked not compliant",
                            systemImage: compliance.isCompliant ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(compliance.isCompliant ? .green : .red)
                        Text(compliance.occurredAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let notes = compliance.notes {
                            Text(notes)
                        }
                    } else {
                        Text("Not answered yet")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        proposedCompliance = true
                        isShowingCheckEditor = true
                    } label: {
                        Label("Yes, I followed my diet", systemImage: "checkmark.circle")
                    }
                    Button {
                        proposedCompliance = false
                        isShowingCheckEditor = true
                    } label: {
                        Label("No, I did not", systemImage: "xmark.circle")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Define your diet",
                    systemImage: "list.clipboard",
                    description: Text("75 Hard asks you to choose and follow your own diet. The app does not prescribe one.")
                )
                Button("Define diet") { isShowingPlanEditor = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Diet")
        .sheet(isPresented: $isShowingPlanEditor) {
            NavigationStack {
                DietPlanEditorView(viewModel: viewModel, plan: plan)
            }
        }
        .sheet(isPresented: $isShowingCheckEditor) {
            NavigationStack {
                DietCheckEditorView(
                    viewModel: viewModel,
                    isCompliant: proposedCompliance,
                    existingNotes: viewModel.dietCompliance?.notes
                )
            }
        }
    }

    private var plan: DietPlan? { viewModel.dashboard?.attempt.dietPlan }
}

private struct DietPlanEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var rules: String
    @State private var isSaving = false

    init(viewModel: AppViewModel, plan: DietPlan?) {
        self.viewModel = viewModel
        _name = State(initialValue: plan?.name ?? "")
        _rules = State(initialValue: plan?.rules ?? "")
    }

    var body: some View {
        Form {
            Section("Plan") {
                TextField("Name, such as Whole Foods", text: $name)
                TextEditor(text: $rules)
                    .frame(minHeight: 160)
                    .onChange(of: rules) { _, value in
                        if value.count > 2_000 { rules = String(value.prefix(2_000)) }
                    }
                Text("Describe the rules you chose. This app does not provide dietary or medical advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diet Definition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        let didSave = await viewModel.configureDiet(name: name, rules: rules)
                        isSaving = false
                        if didSave { dismiss() }
                    }
                }
                .disabled(
                    isSaving ||
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }
}

private struct DietCheckEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    let isCompliant: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var isSaving = false

    init(viewModel: AppViewModel, isCompliant: Bool, existingNotes: String?) {
        self.viewModel = viewModel
        self.isCompliant = isCompliant
        _notes = State(initialValue: existingNotes ?? "")
    }

    var body: some View {
        Form {
            Section {
                Label(
                    isCompliant ? "I followed my diet" : "I did not follow my diet",
                    systemImage: isCompliant ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(isCompliant ? .green : .red)
            }
            Section("Notes (optional)") {
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
                    .onChange(of: notes) { _, value in
                        if value.count > 500 { notes = String(value.prefix(500)) }
                    }
            }
            Section {
                Text("You can correct this answer later. This challenge relies on your own honest assessment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diet Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        let didSave = await viewModel.setDietCompliance(
                            isCompliant: isCompliant,
                            notes: notes
                        )
                        isSaving = false
                        if didSave { dismiss() }
                    }
                }
                .disabled(isSaving)
            }
        }
    }
}

private struct ReadingView: View {
    let requirement: RequirementEvaluation
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedEntry: RecordedReading?
    @State private var isShowingEditor = false
    @State private var pendingDeletion: RecordedReading?

    var body: some View {
        List {
            Section("Today's progress") {
                Text("\(currentRequirement.currentValue ?? 0) / \(currentRequirement.targetValue ?? 10) pages")
                    .font(.title2.bold())
                ProgressView(
                    value: Double(currentRequirement.currentValue ?? 0),
                    total: Double(currentRequirement.targetValue ?? 10)
                )
            }

            Section("Reading sessions") {
                if viewModel.readingEntries.isEmpty {
                    ContentUnavailableView(
                        "No reading recorded",
                        systemImage: "book.closed",
                        description: Text("Record the pages you read from a nonfiction book.")
                    )
                } else {
                    ForEach(viewModel.readingEntries) { entry in
                        Button {
                            guard entry.canEdit else { return }
                            selectedEntry = entry
                            isShowingEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.reading.bookTitle ?? "Book")
                                    .font(.headline)
                                Text("Pages \(entry.reading.startingPage)–\(entry.reading.endingPage) • \(entry.reading.pagesRead) pages")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(entry.occurredAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if entry.canEdit {
                                Button("Delete", role: .destructive) { pendingDeletion = entry }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reading")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedEntry = nil
                    isShowingEditor = true
                } label: {
                    Label("Record reading", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                ReadingEditorView(viewModel: viewModel, entry: selectedEntry)
            }
        }
        .confirmationDialog(
            "Delete reading entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete entry", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await viewModel.deleteReading(id: entry.id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Today's reading progress will be recalculated.")
        }
    }

    private var currentRequirement: RequirementEvaluation {
        viewModel.dashboard?.evaluation.requirements.first { $0.id == requirement.id } ?? requirement
    }
}

private struct ReadingEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    let entry: RecordedReading?
    @Environment(\.dismiss) private var dismiss
    @State private var bookTitle: String
    @State private var startingPage: String
    @State private var endingPage: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(viewModel: AppViewModel, entry: RecordedReading?) {
        self.viewModel = viewModel
        self.entry = entry
        _bookTitle = State(initialValue: entry?.reading.bookTitle ?? "")
        _startingPage = State(initialValue: entry.map { String($0.reading.startingPage) } ?? "")
        _endingPage = State(initialValue: entry.map { String($0.reading.endingPage) } ?? "")
    }

    var body: some View {
        Form {
            Section("Book") {
                TextField("Book title", text: $bookTitle)
                    .textInputAutocapitalization(.words)
            }
            Section("Pages") {
                TextField("Starting page", text: $startingPage)
                    .keyboardType(.numberPad)
                TextField("Ending page", text: $endingPage)
                    .keyboardType(.numberPad)
            }
            if let validationMessage {
                Section { Text(validationMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(entry == nil ? "Record Reading" : "Edit Reading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(
                        isSaving ||
                            bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            startingPage.isEmpty || endingPage.isEmpty
                    )
            }
        }
    }

    @MainActor
    private func save() async {
        guard let start = Int(startingPage),
              let end = Int(endingPage),
              start >= 0,
              end > start,
              end - start <= 1_000
        else {
            validationMessage = "Ending page must be after the starting page, with at most 1,000 pages per entry."
            return
        }
        isSaving = true
        let didSave = await viewModel.saveReading(
            id: entry?.id,
            bookID: entry?.reading.bookID,
            bookTitle: bookTitle,
            startingPage: start,
            endingPage: end
        )
        isSaving = false
        if didSave { dismiss() }
    }
}

private struct ProgressPhotoView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingDeleteConfirmation = false
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                if let data = viewModel.progressPhotoData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Today's private progress photo")
                    if let photo = viewModel.progressPhoto {
                        Text("Saved \(photo.occurredAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "No photo saved today",
                        systemImage: "camera",
                        description: Text("Take a private photo or use the dashboard checkbox to track completion without attaching an image.")
                    )
                }
            }

            Section("Add or replace") {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isSaving)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Existing Photo", systemImage: "photo.on.rectangle")
                }
                .disabled(isSaving)
            }

            if viewModel.progressPhoto != nil {
                Section {
                    Button("Delete Today's Photo", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }

            Section("Privacy") {
                Text("Progress photos are stored only in the app's protected private container. They are never shared with a group unless you explicitly choose to share them in a future feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Progress Photo")
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                Task { await save(image: image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { return }
                await save(image: image)
                selectedPhotoItem = nil
            }
        }
        .confirmationDialog(
            "Delete today's progress photo?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                Task { await viewModel.deleteProgressPhoto() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The protected image file will be permanently removed from this device.")
        }
    }

    @MainActor
    private func save(image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        isSaving = true
        _ = await viewModel.saveProgressPhoto(jpegData: data)
        isSaving = false
    }
}

@MainActor
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
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
