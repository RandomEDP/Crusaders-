import SwiftUI
import CrusadersKit

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .shadow(color: Theme.ink.opacity(0.35), radius: 8, y: 4)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Crusaders")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home.logo")

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
            // The logo already says "Crusaders"; the title stays for the back button and VoiceOver.
            .navigationTitle("Crusaders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
            .parchmentScreen()
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
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.crimson)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.title)
                    .font(.gothic(.title))
                Text(destination.subtitle)
                    .font(.serif(.subheadline))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.inkSoft)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 96)
        .paperCard(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeView().environment(AppModel()).crusadersTheme()
}
