import Foundation
import CrusadersKit

extension CreatureLibrary {
    /// The creature library the app runs with. Follows the same iCloud and creator rules as Library > Items
    /// (see `LibrarySync`): `-creatorMode` turns on creator tools in Debug builds.
    static func makeDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        cloudKitEnabled: Bool = ItemLibrary.cloudKitEnabledInBuild
    ) -> CreatureLibrary {
        let creatures = (try? SRDCreatures.load()) ?? []
        switch LibrarySync.choose(arguments: arguments, cloudKitEnabled: cloudKitEnabled) {
        case .cloudKit:
            return CreatureLibrary(baseCreatures: creatures, store: CloudKitCreatureStore(), creatorAccess: CloudKitCreatorAccess())
        case .local(let access):
            return CreatureLibrary(baseCreatures: creatures, store: InMemoryCreatureStore(), creatorAccess: access)
        }
    }
}
