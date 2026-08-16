import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.dashboard == nil {
                    ProgressView("Loading challenge…")
                } else if let dashboard = viewModel.dashboard {
                    MainTabView(snapshot: dashboard, viewModel: viewModel)
                } else {
                    OnboardingView(viewModel: viewModel)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "Please try again.")
            }
        }
    }
}

struct MainTabView: View {
    let snapshot: DashboardSnapshot
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            DashboardView(snapshot: snapshot, viewModel: viewModel)
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            GroupsView(viewModel: viewModel)
                .tabItem {
                    Label("Groups", systemImage: "person.3")
                }
                .badge(viewModel.myGroups.isEmpty ? 0 : nil)

            ExternalWorkoutsView(viewModel: viewModel)
                .tabItem {
                    Label("Integrations", systemImage: "heart.text.square")
                }
        }
        .task {
            await viewModel.loadGroups()
            await viewModel.loadExternalWorkoutSources()
            await viewModel.loadSyncStatus()
        }
        .refreshable {
            await viewModel.load()
            await viewModel.loadGroups()
            await viewModel.loadAvailableExternalWorkouts()
            await viewModel.loadSyncStatus()
        }
    }
}