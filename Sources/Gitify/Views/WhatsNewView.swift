import SwiftUI

/// Wrapper to satisfy `Identifiable` for the `sheet(item:)` API.
struct WhatsNewContent: Identifiable {
    let id = UUID()
    let items: [ReleaseEntry]
}

/// Shows release notes for the current version and recent prior releases.
struct WhatsNewView: View {
    let entries: [ReleaseEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                if let latest = entries.first {
                    Text("What\u{2019}s New in \(latest.version)")
                        .font(.title2.bold())
                    Text(latest.date)
                        .foregroundStyle(.secondary)
                } else {
                    Text("What\u{2019}s New")
                        .font(.title2.bold())
                }
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Scrollable content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Latest release
                if let latest = entries.first {
                    releaseSection(latest)
                }

                // Recent updates (up to 3 prior releases)
                let recent = Array(entries.dropFirst().prefix(3))
                if !recent.isEmpty {
                    Text("Recent Updates")
                        .font(.title3.bold())
                        .padding(.top, 4)

                    ForEach(recent) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.version).font(.headline)
                                Text(entry.date).font(.caption).foregroundStyle(.secondary)
                            }
                            releaseSection(entry)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Renders the sections (Features, Bug Fixes, etc.) for a single release.
    private func releaseSection(_ entry: ReleaseEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Label(section.heading, systemImage: section.heading.lowercased().contains("fix") ? "ladybug" : "star")
                        .font(.subheadline.bold())
                        .foregroundStyle(section.heading.lowercased().contains("fix") ? .orange : .blue)

                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(.secondary)
                            Text(item)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Continue") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
}
