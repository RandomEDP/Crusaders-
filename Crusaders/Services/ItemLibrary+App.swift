import Foundation
import CrusadersKit

extension ItemLibrary {
    /// Whether this build is signed for iCloud. Set by `CLOUDKIT_ENABLED` in project.yml.
    /// CloudKit must never be touched when this is off: without the entitlement the app would crash.
    nonisolated static var cloudKitEnabledInBuild: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "CrusadersCloudKitEnabled") as? String
        return value?.uppercased() == "YES"
    }

    /// The item library the app runs with.
    ///
    /// Builds with iCloud turned on use CloudKit (always in Release; in Debug only with `-useCloudKit`).
    /// Otherwise edits stay in memory: Debug builds can try creator tools with `-creatorMode`,
    /// and Release builds are view-only until iCloud is set up.
    static func makeDefault(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        cloudKitEnabled: Bool = cloudKitEnabledInBuild
    ) -> ItemLibrary {
        let items = (try? SRDItems.load()) ?? []
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        if cloudKitEnabled && (!isDebug || arguments.contains("-useCloudKit")) {
            return ItemLibrary(baseItems: items, store: CloudKitItemOverrideStore(), creatorAccess: CloudKitCreatorAccess())
        }
        let access: CreatorAccess
        if isDebug && arguments.contains("-creatorMode") {
            access = FixedCreatorAccess(isCreator: true)
        } else if cloudKitEnabled {
            access = FixedCreatorAccess(isCreator: false)
        } else {
            access = FixedCreatorAccess(CreatorStatus(
                isCreator: false,
                problem: "Creator editing turns on once iCloud is set up for this app."
            ))
        }
        return ItemLibrary(baseItems: items, store: InMemoryItemOverrideStore(), creatorAccess: access)
    }
}
