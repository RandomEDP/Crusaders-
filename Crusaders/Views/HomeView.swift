import SwiftUI
import CrusadersKit

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(HomeDestination.allCases) { destination in
                        NavigationLink(value: destination) {
                            HomeTile(destination: destination)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.\(destination.rawValue)")
                    }
                }
                .padding()
            }
            .navigationTitle("Crusaders")
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .characters: CharactersView()
                case .campaigns: CampaignsView()
                case .library: LibraryView()
                }
            }
        }
    }
}

private struct HomeTile: View {
    let destination: HomeDestination

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.title)
                    .font(.title2.bold())
                Text(destination.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeView().environment(AppModel())
}
