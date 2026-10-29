import CoreLocation
import SwiftUI

struct SearchView: View {
    let near: CLLocationCoordinate2D?
    let onPick: (PlaceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                } else if searched && results.isEmpty {
                    Text("Nothing found. Try an address, a place name, or coordinates like 32.95, -96.89.")
                        .foregroundStyle(.secondary)
                }

                ForEach(results) { place in
                    Button {
                        onPick(place)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .foregroundStyle(Theme.ink)
                            if !place.subtitle.isEmpty {
                                Text(place.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Place, address or lat, lon")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .task(id: query) {
                // Debounce typing.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, query.count >= 3 else { return }
                await search()
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        isSearching = true
        let found = await RoutePlanner.search(query, near: near)
        isSearching = false
        searched = true
        results = found
    }
}
