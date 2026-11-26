import Foundation

/// The three top-level areas reachable from the home screen.
public enum HomeDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case characters
    case campaigns
    case library

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .characters: return "Characters"
        case .campaigns: return "Campaigns"
        case .library: return "Library"
        }
    }

    public var subtitle: String {
        switch self {
        case .characters: return "Your heroes and their stories"
        case .campaigns: return "Create or join an adventure"
        case .library: return "Creatures, weapons, armour and more"
        }
    }

    /// SF Symbol name used for the home screen tile.
    public var systemImage: String {
        switch self {
        case .characters: return "person.crop.circle"
        case .campaigns: return "map"
        case .library: return "books.vertical"
        }
    }
}
