import Foundation

/// Parses `git for-each-ref` output formatted with US-separated fields:
/// refname, objecttype, objectname, *objectname (peeled), HEAD marker,
/// upstream:short, upstream:track.
enum RefParser {
    static func parse(_ output: String) -> [Ref] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 7 else { return nil }

            let refname = fields[0]
            let objectType = fields[1]
            let objectName = fields[2]
            let peeled = fields[3]
            let isHead = fields[4] == "*"
            let upstreamShort = fields[5].isEmpty ? nil : fields[5]
            let (ahead, behind) = parseTrack(fields[6])

            // For annotated tags, prefer the peeled commit SHA.
            let target = (objectType == "tag" && !peeled.isEmpty) ? peeled : objectName

            let kind: Ref.Kind
            let name: String
            if refname.hasPrefix("refs/heads/") {
                kind = .localBranch
                name = String(refname.dropFirst("refs/heads/".count))
            } else if refname.hasPrefix("refs/remotes/") {
                kind = .remoteBranch
                name = String(refname.dropFirst("refs/remotes/".count))
            } else if refname.hasPrefix("refs/tags/") {
                kind = .tag
                name = String(refname.dropFirst("refs/tags/".count))
            } else {
                return nil
            }

            // HEAD/track only meaningful for local branches.
            return Ref(
                id: refname, kind: kind, name: name, targetSHA: target,
                isHead: kind == .localBranch && isHead,
                upstream: kind == .localBranch ? upstreamShort : nil,
                ahead: kind == .localBranch ? ahead : nil,
                behind: kind == .localBranch ? behind : nil
            )
        }
    }

    /// `upstream:track` looks like `[ahead 1, behind 2]`, `[ahead 3]`, `[gone]`, or empty.
    private static func parseTrack(_ field: String) -> (Int?, Int?) {
        guard field.hasPrefix("["), field.hasSuffix("]") else { return (nil, nil) }
        let inner = field.dropFirst().dropLast()
        if inner == "gone" { return (nil, nil) }
        var ahead: Int?
        var behind: Int?
        for part in inner.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let value = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = value }
            else if words[0] == "behind" { behind = value }
        }
        return (ahead, behind)
    }
}
