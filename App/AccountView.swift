import SwiftUI

struct AccountView: View {
    let account: Account
    @EnvironmentObject private var session: AppSession
    @State private var showsSettings=false
    @State private var confirmsLogout=false
    private var roleLabel: LocalizedStringKey {
        switch account.effectiveRole {
        case "merchant": return "account.role.merchant"
        case "player": return "account.role.player"
        case "club": return "account.role.club"
        default: return "account.role.other"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("account.details") {
                    LabeledContent("account.name",value:account.nickname)
                    LabeledContent("account.id",value:String(account.id))
                    LabeledContent("account.role") { Text(roleLabel) }
                }
                ProfileAccountLinks(reader:session.profileReader,participantCoordinator:session.participantCoordinator)
                Section {
                    NavigationLink { MessagingHomeView(reader:session.messagingReader,senderForConversation:{ session.messageSender(for:$0) }).id(session.messagingReader.identity) } label: {
                        Label("messaging.title",systemImage:"bubble.left.and.bubble.right")
                    }.accessibilityIdentifier("account.messages")
                    NavigationLink { ClubHomeView(reader:session) } label: { Label("club.title",systemImage:"person.3") }
                        .accessibilityIdentifier("account.clubs")
                }
                Section {
                    NavigationLink { MerchantHomeView(reader:session) } label: {
                        Label("merchant.title",systemImage:"storefront")
                    }.accessibilityIdentifier("account.merchant")
                }
                Section {
                    Button("auth.signOut",role:.destructive) { confirmsLogout=true }
                }
            }
            .navigationTitle("account.title")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("settings.title",systemImage:"gearshape") { showsSettings=true }
                }
            }
            .sheet(isPresented:$showsSettings) { SettingsView() }
            .confirmationDialog("auth.signOutConfirm",isPresented:$confirmsLogout,titleVisibility:.visible) {
                Button("auth.signOut",role:.destructive) { Task { await session.logout() } }
                Button("action.cancel",role:.cancel) {}
            }
        }
    }
}
