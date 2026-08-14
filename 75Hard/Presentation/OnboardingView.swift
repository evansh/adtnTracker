import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var startDate = Date()

    var body: some View {
        Form {
            Section {
                Text("Build consistency one day at a time.")
                    .font(.title2.bold())
                Text("Your daily progress stays on this device by default.")
                    .foregroundStyle(.secondary)
            }
            Section("Challenge") {
                LabeledContent("Program", value: "75 Hard")
                DatePicker(
                    "Start date",
                    selection: $startDate,
                    in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                    displayedComponents: .date
                )
            }
            Section {
                Button("Start 75 Hard") {
                    let day = LocalDay(startDate, calendar: .autoupdatingCurrent)
                    Task { await viewModel.startChallenge(on: day) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Welcome")
    }
}
