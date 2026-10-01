import SwiftUI

@MainActor
struct ActivityBrowserView: View {
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    @State private var items: [ActivitySummary] = []
    @State private var query = ""
    // A search draft must not change the query used for the current page set.
    @State private var appliedQuery = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var failed = false
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            // A concrete root keeps task/navigation modifiers alive across loading states.
            ZStack {
                if !reader.isConfigured {
                    ContentUnavailableView("activity.unavailable",systemImage:"network.slash",description:Text("auth.notConfigured"))
                } else if isLoading && items.isEmpty {
                    ProgressView("activity.loading")
                } else if failed && items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("activity.loadFailed").accessibilityIdentifier("activity.list.error")
                        } icon: { Image(systemName:"wifi.exclamationmark") }
                    } actions: {
                        Button("action.retry") { Task { await load(reset:true) } }
                            .accessibilityIdentifier("activity.list.retry")
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("activity.empty").accessibilityIdentifier("activity.list.empty")
                        } icon: { Image(systemName:"map") }
                    } description: { Text("activity.emptyHint") }
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink { ActivityDetailView(id:item.id,reader:reader,playReaderForActivity:playReaderForActivity) } label: { ActivityRow(item:item) }
                                .accessibilityIdentifier("activity.row.\(item.id)")
                        }
                        if hasMore || failed {
                            Button(failed ? LocalizedStringKey("action.retry") : LocalizedStringKey("activity.loadMore")) { Task { await load(reset:false) } }
                                .disabled(isLoading)
                                .accessibilityIdentifier("activity.list.loadMore")
                        }
                        if isLoading { ProgressView() }
                    }
                    .refreshable { await load(reset:true) }
                    .accessibilityIdentifier("activity.list.content")
                }
            }
            .navigationTitle("activity.browse")
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"activity.search")
            .onSubmit(of:.search) { Task { await load(reset:true) } }
            .task { await load(reset:true) }
        }
    }
    @MainActor private func load(reset:Bool) async {
        guard reader.isConfigured, reset || !isLoading else { return }
        if reset { generation += 1;items=[];page=0;hasMore=false;appliedQuery=query }
        let operation=generation
        let next=page+1
        let keyword=appliedQuery
        isLoading=true;failed=false
        defer { if generation == operation { isLoading=false } }
        do {
            let result=try await reader.activities(page:next,keyword:keyword)
            guard generation == operation else { return }
            var existing=Set(items.map(\.id))
            items.append(contentsOf:result.filter { existing.insert($0.id).inserted })
            page=next;hasMore=result.count >= 10
        } catch is CancellationError { }
        catch { if generation == operation { failed=true } }
    }
}

private struct ActivityRow: View {
    let item: ActivitySummary
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(item.name).font(.headline)
            if let start=item.startDate, !start.isEmpty { Label(start,systemImage:"calendar").font(.subheadline) }
            if let place=item.addressName ?? item.address, !place.isEmpty { Label(place,systemImage:"mappin.and.ellipse").font(.subheadline) }
            AmountLabel(amount:item.minimumAmount)
        }
        .padding(.vertical,8)
    }
}

struct AmountLabel: View {
    let amount: Decimal?
    @Environment(\.locale) private var locale
    private var formatted: String? {
        guard let amount else { return nil }
        let formatter=NumberFormatter();formatter.locale=locale;formatter.numberStyle = .decimal
        formatter.minimumFractionDigits=2;formatter.maximumFractionDigits=2
        return formatter.string(from:NSDecimalNumber(decimal:amount))
    }
    var body: some View {
        if let formatted {
            VStack(alignment:.leading,spacing:4) {
                Text(formatted).monospacedDigit()
                Text("activity.currencyUnconfirmed").font(.caption).foregroundStyle(.secondary)
            }
        } else { Text("activity.priceUnknown").foregroundStyle(.secondary) }
    }
}
