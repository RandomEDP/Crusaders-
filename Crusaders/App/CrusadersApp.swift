import SwiftUI
import CrusadersKit

@main
struct CrusadersApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
        }
    }
}
