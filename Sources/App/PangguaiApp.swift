import SwiftUI

@main
struct PangguaiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .onAppear { store.restore() }
        }
    }
}
