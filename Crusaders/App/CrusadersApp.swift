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
                // A PDF shared to the app (Share → Crusaders, from D&D Beyond or Files).
                .onOpenURL { url in
                    if url.isFileURL { model.openSheetPDF(at: url) }
                }
                .sheet(item: $model.pendingImport) { pending in
                    ImportReviewView(result: pending.result)
                        .environment(model)
                        .crusadersTheme()
                }
                .alert("Couldn't import", isPresented: Binding(
                    get: { model.importProblem != nil },
                    set: { if !$0 { model.importProblem = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.importProblem ?? "")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadCharacters()
            }
        }
    }
}
