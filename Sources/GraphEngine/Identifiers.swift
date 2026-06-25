import Foundation

/// A stable identity for a node in a ``Graph``.
///
/// Nodes are referenced by id everywhere (edges, results, errors) so that the
/// graph can be a plain value type and the future UI can hold onto a reference
/// across recomputes.
public struct NodeID: Hashable, Sendable {
    let raw: UUID

    init(_ raw: UUID = UUID()) {
        self.raw = raw
    }
}

extension NodeID: CustomStringConvertible {
    public var description: String { raw.uuidString }
}

/// One specific output port of one specific node — the *source* end of a wire.
///
/// `port` is the zero-based index into the node kind's declared output ports.
/// Most nodes have a single output, so ``init(_:_:)`` defaults it to `0`.
public struct OutputEndpoint: Hashable, Sendable {
    public let node: NodeID
    public let port: Int

    public init(_ node: NodeID, _ port: Int = 0) {
        self.node = node
        self.port = port
    }
}

/// One specific input port of one specific node — the *target* end of a wire.
///
/// Unlike outputs, an input port must always name the port explicitly because a
/// binary operation distinguishes its operands (`a` − `b` is not `b` − `a`).
public struct InputEndpoint: Hashable, Sendable {
    public let node: NodeID
    public let port: Int

    public init(_ node: NodeID, _ port: Int) {
        self.node = node
        self.port = port
    }
}
