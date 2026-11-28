import SwiftUI
import CoreData
import CrusadersKit

@main
struct CrusadersApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .crusadersTheme()
                // iCloud brings in characters edited on other devices.
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
                    model.reloadCharacters()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadCharacters()
            }
        }
    }
}
