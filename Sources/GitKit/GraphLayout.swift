import Foundation

/// Assigns lanes (columns) to commits and computes the connecting edges, producing a
/// `CommitGraph` for rendering.
///
/// The commits must be in display order (newest first, topologically ordered — exactly
/// what `git log --topo-order` yields). The algorithm walks rows top-to-bottom keeping a
/// set of *active lanes*; each lane records the SHA of the commit it is currently routing
/// toward. When a commit is reached, every lane routing to it converges into its node, and
/// its parents are routed onward — the first parent continuing in the commit's own lane and
/// any additional (merge) parents taking newly allocated lanes.
public enum GraphLayout {
    public static func layout(_ commits: [Commit]) -> CommitGraph {
        var lanes: [String?] = []   // lanes[c] = SHA that column c is routing toward
        var nodes: [CommitNode] = []
        var width = 0

        func firstFreeLane() -> Int {
            if let idx = lanes.firstIndex(where: { $0 == nil }) { return idx }
            lanes.append(nil)
            return lanes.count - 1
        }

        for (row, commit) in commits.enumerated() {
            let stateBefore = lanes

            // Lanes routing to this commit (its children, from rows above).
            let incoming = stateBefore.indices.filter { stateBefore[$0] == commit.id }
            let commitLane = incoming.min() ?? firstFreeLane()

            // Those lanes have reached the commit; free them so they can be reused.
            for k in incoming { lanes[k] = nil }
            lanes[commitLane] = nil

            // Route parents onward, reusing an existing lane if one already targets a parent.
            var outgoing: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    outgoing.append(existing)
                } else {
                    let lane = (index == 0) ? commitLane : firstFreeLane()
                    lanes[lane] = parent
                    outgoing.append(lane)
                }
            }

            // Branches unrelated to this commit pass straight through.
            let incomingSet = Set(incoming)
            let passThrough = stateBefore.indices.filter { k in
                stateBefore[k] != nil && stateBefore[k] != commit.id && !incomingSet.contains(k)
            }

            width = max(width, lanes.count, commitLane + 1)
            nodes.append(CommitNode(
                id: commit.id, row: row, lane: commitLane,
                incoming: incoming, outgoing: outgoing, passThrough: passThrough))

            // Keep the lane array compact so the gutter doesn't grow without bound.
            while let last = lanes.last, last == nil { lanes.removeLast() }
        }

        return CommitGraph(nodes: nodes, width: max(width, 1))
    }
}
