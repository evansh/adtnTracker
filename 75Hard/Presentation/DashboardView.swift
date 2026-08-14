import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List {
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
                    HStack {
                        Image(systemName: icon(for: requirement.status))
                            .foregroundStyle(color(for: requirement.status))
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
                        Text(label(for: requirement.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
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

    private func icon(for status: RequirementStatus) -> String {
        switch status {
        case .complete: "checkmark.circle.fill"
        case .automaticallyVerified: "checkmark.seal.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .notComplete: "circle"
        }
    }

    private func color(for status: RequirementStatus) -> Color {
        status.isSatisfied ? .green : (status == .inProgress ? .orange : .secondary)
    }

    private func label(for status: RequirementStatus) -> String {
        switch status {
        case .complete: "Complete"
        case .automaticallyVerified: "Verified"
        case .inProgress: "In progress"
        case .notComplete: "Not complete"
        }
    }
}
