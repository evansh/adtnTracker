import SwiftUI

@main
struct Hard75App: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        let dependencies = (try? DependencyContainer.live()) ?? .fallback()
        _viewModel = StateObject(wrappedValue: AppViewModel(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .task { await viewModel.load() }
        }
    }
}
