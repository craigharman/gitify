import SwiftUI
import GitKit

struct StashesView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        if viewModel.stashes.isEmpty {
            ContentUnavailableView("No Stashes", systemImage: "tray.full",
                                   description: Text("Stashed changes will appear here."))
        } else {
            List(viewModel.stashes) { stash in
                HStack(spacing: 8) {
                    Image(systemName: "tray.full").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stash.message).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(stash.id).monospaced()
                            if let branch = stash.branch { Text("on \(branch)") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }
}
