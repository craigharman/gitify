import SwiftUI
import GitKit

/// A conflict resolver: shows each conflict region's "ours" and "theirs" sides and lets you
/// pick one (or both), then writes the resolved file and stages it.
struct ConflictEditorView: View {
    let viewModel: RepositoryViewModel
    let path: String
    @Environment(\.dismiss) private var dismiss

    enum Choice: Hashable { case ours, theirs, both, unresolved }

    @State private var segments: [ConflictSegment] = []
    @State private var choices: [Int: Choice] = [:]
    @State private var loaded = false

    private var language: String { (path as NSString).pathExtension.lowercased() }

    private var conflictIndices: [Int] {
        segments.indices.filter { if case .conflict = segments[$0] { return true }; return false }
    }
    private var unresolvedCount: Int {
        conflictIndices.filter { (choices[$0] ?? .unresolved) == .unresolved }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolve Conflicts").font(.headline)
                    Text(path).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(unresolvedCount) unresolved").foregroundStyle(unresolvedCount == 0 ? .green : .orange)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        switch segment {
                        case let .text(text):
                            codeBlock(text, background: .clear)
                        case let .conflict(ours, theirs, _):
                            conflictRegion(index: index, ours: ours, theirs: theirs)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.body, design: .monospaced))

            Divider()
            HStack {
                Button("Open in Editor") {
                    NSWorkspace.shared.open(viewModel.ref.url.appendingPathComponent(path))
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Resolve & Stage") {
                    Task { await viewModel.resolveFile(path: path, contents: resolvedContents()); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(unresolvedCount > 0)
            }
            .padding()
        }
        .frame(width: 720, height: 560)
        .task {
            guard !loaded else { return }
            loaded = true
            if let contents = await viewModel.fileContents(path) {
                segments = ConflictParser.parse(contents)
            }
        }
    }

    private func conflictRegion(index: Int, ours: String, theirs: String) -> some View {
        let choice = choices[index] ?? .unresolved
        return VStack(spacing: 0) {
            sideHeader("Current (ours)", chosen: choice == .ours || choice == .both, color: .green) {
                choices[index] = (choice == .ours) ? .unresolved : .ours
            }
            codeBlock(ours, background: .green.opacity(0.12))
            sideHeader("Incoming (theirs)", chosen: choice == .theirs || choice == .both, color: .blue) {
                choices[index] = (choice == .theirs) ? .unresolved : .theirs
            }
            codeBlock(theirs, background: .blue.opacity(0.12))
            HStack {
                Button("Use Both") { choices[index] = .both }
                Spacer()
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .padding(.vertical, 6).padding(.horizontal, 8)
    }

    private func sideHeader(_ title: String, chosen: Bool, color: Color, toggle: @escaping () -> Void) -> some View {
        HStack {
            Button(action: toggle) {
                Label(title, systemImage: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? color : .secondary)
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .font(.caption.bold())
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08))
    }

    private func codeBlock(_ text: String, background: Color) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let highlighted = lines.enumerated().reduce(AttributedString()) { result, pair in
            var out = result
            if pair.offset > 0 { out += AttributedString("\n") }
            out += SyntaxHighlighter.highlight(String(pair.element), language: language)
            return out
        }
        return Text(text.isEmpty ? AttributedString(" ") : highlighted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(background)
            .textSelection(.enabled)
    }

    private func resolvedContents() -> String {
        var parts: [String] = []
        for (index, segment) in segments.enumerated() {
            switch segment {
            case let .text(text):
                parts.append(text)
            case let .conflict(ours, theirs, _):
                switch choices[index] ?? .unresolved {
                case .ours: parts.append(ours)
                case .theirs: parts.append(theirs)
                case .both: parts.append(ours + "\n" + theirs)
                case .unresolved: parts.append(ours) // shouldn't happen (button disabled)
                }
            }
        }
        return parts.joined(separator: "\n")
    }
}
