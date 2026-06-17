import SwiftUI

/// A lightweight block-level Markdown renderer for README previews. Handles headings,
/// paragraphs, bullet/numbered lists, fenced code blocks, block quotes, and horizontal
/// rules, with inline formatting (bold/italic/code/links) via `AttributedString`.
struct MarkdownView: View {
    let markdown: String

    private var blocks: [Block] { Block.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case let .paragraph(text):
            Text(inline(text))
        case let .code(code):
            ScrollView(.horizontal) {
                Text(code).font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        case let .listItem(ordered, marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered ? "\(marker)." : "•").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
        case let .quote(text):
            HStack(spacing: 8) {
                Rectangle().fill(.secondary).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// A parsed Markdown block.
    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String)
        case listItem(ordered: Bool, marker: String, text: String)
        case quote(String)
        case rule

        static func parse(_ markdown: String) -> [Block] {
            let lines = markdown.components(separatedBy: "\n")
            var blocks: [Block] = []
            var i = 0

            func isSpecial(_ line: String) -> Bool {
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```")
                    || t.hasPrefix(">") || isRule(t) || listMarker(line) != nil
            }

            while i < lines.count {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("```") {
                    i += 1
                    var code: [String] = []
                    while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        code.append(lines[i]); i += 1
                    }
                    i += 1 // closing fence
                    blocks.append(.code(code.joined(separator: "\n")))
                } else if trimmed.isEmpty {
                    i += 1
                } else if trimmed.hasPrefix("#") {
                    let hashes = trimmed.prefix { $0 == "#" }
                    let text = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes.count, text: text)); i += 1
                } else if isRule(trimmed) {
                    blocks.append(.rule); i += 1
                } else if trimmed.hasPrefix(">") {
                    blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))); i += 1
                } else if let marker = listMarker(line) {
                    blocks.append(.listItem(ordered: marker.ordered, marker: marker.number, text: marker.text)); i += 1
                } else {
                    var para = [trimmed]; i += 1
                    while i < lines.count, !isSpecial(lines[i]) {
                        para.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                    }
                    blocks.append(.paragraph(para.joined(separator: " ")))
                }
            }
            return blocks
        }

        private static func isRule(_ t: String) -> Bool {
            (t == "---" || t == "***" || t == "___") ||
            (t.count >= 3 && (t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" }))
        }

        private static func listMarker(_ line: String) -> (ordered: Bool, number: String, text: String)? {
            let t = line.trimmingCharacters(in: .whitespaces)
            for bullet in ["- ", "* ", "+ "] where t.hasPrefix(bullet) {
                return (false, "", String(t.dropFirst(bullet.count)))
            }
            // Ordered: "1. text"
            if let dot = t.firstIndex(of: "."), t[t.startIndex..<dot].allSatisfy(\.isNumber),
               t.index(after: dot) < t.endIndex, t[t.index(after: dot)] == " " {
                let number = String(t[t.startIndex..<dot])
                let text = String(t[t.index(dot, offsetBy: 2)...])
                return (true, number, text)
            }
            return nil
        }
    }
}
