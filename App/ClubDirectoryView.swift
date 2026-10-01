import SwiftUI

@MainActor
struct ClubDirectoryView<Reader: ClubReading & ObservableObject>: View {
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    @State private var searchText = ""
    @State private var submittedName = ""
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.directory", onSignIn: onSignIn,
                       load: { try await reader.clubDirectory(name: submittedName.isEmpty ? nil : submittedName) }) { rows in
            if rows.isEmpty {
                ClubEmptyState(title: "club.emptyDirectory", hint: "club.emptyDirectoryHint", identifier: "club.directory.empty")
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, club in
                        NavigationLink {
                            ClubDetailView(id: club.id, reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator)
                        } label: { ClubRow(club: club) }.accessibilityIdentifier("club.directory.\(club.id)")
                    }
                }
            }
        }
        .id(submittedName)
        .navigationTitle("club.directory")
        .searchable(text: $searchText, prompt: "club.searchPrompt")
        .onSubmit(of: .search) { submittedName = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: searchText) { _, value in if value.isEmpty { submittedName = "" } }
        .onChange(of: reader.clubIdentity) { _, _ in searchText = ""; submittedName = "" }
    }
}

/// /my owns only the owned section; joined clubs remain separately sourced from /home.
@MainActor
struct ClubOwnedView<Reader: ClubReading & ObservableObject>: View {
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.owned", requiresSignIn: true,
                       onSignIn: onSignIn, load: { try await reader.clubOwned() }) { rows in
            if rows.isEmpty {
                ClubEmptyState(title: "club.emptyOwned", hint: "club.emptyOwnedHint", identifier: "club.owned.empty")
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, club in
                        NavigationLink {
                            ClubDetailView(id: club.id, reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator)
                        } label: { ClubRow(club: club) }.accessibilityIdentifier("club.owned.\(club.id)")
                    }
                }
            }
        }.navigationTitle("club.owned")
    }
}
