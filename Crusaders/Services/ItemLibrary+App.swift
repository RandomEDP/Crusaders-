import Foundation
import CrusadersKit

extension ItemLibrary {
    /// The item library the app runs with.
    ///
    /// Release builds (TestFlight, App Store) always use iCloud. Debug builds, including CI tests,
    /// keep edits in memory so they run without iCloud signing. In Debug:
    /// - `-useCloudKit` uses iCloud anyway (needs a signed build).
    /// - `-creatorMode` turns on creator tools for the in-memory library.
    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments) -> ItemLibrary {
        let items = (try? SRDItems.load()) ?? []
        #if DEBUG
        let useCloud = arguments.contains("-useCloudKit")
        #else
        let useCloud = true
        #endif
        if useCloud {
            return ItemLibrary(baseItems: items, store: CloudKitItemOverrideStore(), creatorAccess: CloudKitCreatorAccess())
        }
        return ItemLibrary(
            baseItems: items,
            store: InMemoryItemOverrideStore(),
            creatorAccess: FixedCreatorAccess(isCreator: arguments.contains("-creatorMode"))
        )
    }
}
