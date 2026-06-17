import SwiftUI

/// A lightweight, per-line syntax highlighter for diff display. It colors line comments,
/// strings, numbers, and a common keyword set — not a full parser, but enough to make code
/// diffs readable across the popular languages. Block comments aren't tracked across lines.
enum SyntaxHighlighter {
    enum Theme {
        static let keyword = Color(.sRGB, red: 0.78, green: 0.36, blue: 0.64, opacity: 1)
        static let string = Color(.sRGB, red: 0.76, green: 0.30, blue: 0.24, opacity: 1)
        static let comment = Color.secondary
        static let number = Color(.sRGB, red: 0.16, green: 0.46, blue: 0.74, opacity: 1)
    }

    /// Highlights one line of `language` (a lowercased file extension).
    static func highlight(_ line: String, language ext: String) -> AttributedString {
        var out = AttributedString("")
        var plain = ""
        let chars = Array(line)
        let keywords = keywordSet(for: ext)
        let hashComments = ["py", "rb", "sh", "bash", "zsh", "yml", "yaml", "toml", "pl", "r"].contains(ext)

        func append(_ text: String, _ color: Color?) {
            var piece = AttributedString(text)
            if let color { piece.foregroundColor = color }
            out += piece
        }
        func flushPlain() { if !plain.isEmpty { append(plain, nil); plain = "" } }

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // Line comments — colour the remainder of the line.
            if (ch == "/" && i + 1 < chars.count && chars[i + 1] == "/") || (hashComments && ch == "#") {
                flushPlain(); append(String(chars[i...]), Theme.comment); return out
            }
            // Strings.
            if ch == "\"" || ch == "'" || ch == "`" {
                flushPlain()
                let start = i; i += 1
                while i < chars.count, chars[i] != ch { if chars[i] == "\\" { i += 1 }; i += 1 }
                i = min(i + 1, chars.count)
                append(String(chars[start..<i]), Theme.string); continue
            }
            // Numbers.
            if ch.isNumber {
                flushPlain()
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "x"
                    || ("a"..."f").contains(chars[i]) { i += 1 }
                append(String(chars[start..<i]), Theme.number); continue
            }
            // Identifiers / keywords.
            if ch.isLetter || ch == "_" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
                let word = String(chars[start..<i])
                if keywords.contains(word) { flushPlain(); append(word, Theme.keyword) } else { plain += word }
                continue
            }
            plain.append(ch); i += 1
        }
        flushPlain()
        return out
    }

    private static let common: Set<String> = [
        "if", "else", "for", "while", "return", "break", "continue", "switch", "case",
        "default", "do", "try", "catch", "throw", "throws", "import", "true", "false",
        "null", "nil", "new", "class", "struct", "enum", "func", "function", "def", "var",
        "let", "const", "public", "private", "protected", "static", "final", "void", "int",
        "string", "bool", "async", "await", "in", "is", "as", "self", "this", "super",
        "extends", "implements", "interface", "protocol", "extension", "guard", "where",
        "type", "typedef", "namespace", "using", "package", "module", "from", "and", "or", "not",
    ]

    private static func keywordSet(for ext: String) -> Set<String> { common }
}
