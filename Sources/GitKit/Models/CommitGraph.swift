import Foundation

/// The placement of one commit within the rendered graph, plus the edge segments that
/// pass through its row. Columns ("lanes") are stable indices: a lane keeps the same
/// column from the commit that opens it down to the commit that closes it, so edges in
/// adjacent rows line up when drawn.
public struct CommitNode: Identifiable, Sendable, Hashable {
    public let id: String      // commit SHA
    public let row: Int
    /// Column of the commit dot.
    public let lane: Int
    /// Columns at the top of this row that connect down into the node (child edges).
    public let incoming: [Int]
    /// Columns at the bottom of this row that leave the node toward its parents.
    public let outgoing: [Int]
    /// Columns carrying unrelated branches straight through this row (no node contact).
    public let passThrough: [Int]

    public init(id: String, row: Int, lane: Int,
                incoming: [Int], outgoing: [Int], passThrough: [Int]) {
        self.id = id
        self.row = row
        self.lane = lane
        self.incoming = incoming
        self.outgoing = outgoing
        self.passThrough = passThrough
    }
}

/// A laid-out commit graph. `nodes` is parallel to the input commit list (same order).
public struct CommitGraph: Sendable {
    public let nodes: [CommitNode]
    /// Maximum number of simultaneous lanes — used to size the graph gutter.
    public let width: Int

    public init(nodes: [CommitNode], width: Int) {
        self.nodes = nodes
        self.width = width
    }

    public static let empty = CommitGraph(nodes: [], width: 0)
}
