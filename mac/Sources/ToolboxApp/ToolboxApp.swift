import SwiftUI

@main
struct ToolboxApp: App {
    @StateObject private var store = ToolStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: store)
                .frame(minWidth: 880, minHeight: 600)
                .preferredColorScheme(.dark)
                .task { await store.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
    }
}
