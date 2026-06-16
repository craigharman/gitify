import SwiftUI
import GitKit

/// Generic list of refs (remote branches or tags).
struct RefListView: View {
    let title: String
    let refs: [Ref]
    let symbol: String

    var body: some View {
        if refs.isEmpty {
            ContentUnavailableView(title, systemImage: symbol,
                                   description: Text("Nothing here yet."))
        } else {
            List(refs) { ref in
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                    Text(ref.name)
                    Spacer()
                    Text(ref.targetSHA.prefix(7)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .navigationTitle(title)
        }
    }
}
