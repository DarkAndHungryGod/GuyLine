import QuantityKernel

/// Why a node failed to produce a value during a recompute.
///
/// These are the engine-level analogues of ``KernelError``: recoverable, and
/// meant to be rendered as feedback on the offending node rather than thrown out
/// of the program.
public enum NodeError: Error, Equatable, Sendable {
    /// A required input port has no wire feeding it.
    case missingInput(port: Int)
    /// An input is wired to a node that itself failed, so this node cannot run.
    case upstreamFailure
    /// The node participates in a dependency cycle and cannot be ordered.
    case cycle
    /// The node's own computation was dimensionally invalid (e.g. `m + kg`).
    case kernel(KernelError)
}

/// The outcome of evaluating a ``Graph`` once.
///
/// `values` and `errors` partition the nodes: a node that ran successfully
/// contributes its output endpoints to `values`; a node that could not run
/// contributes a reason to `errors`.
public struct GraphResult: Equatable, Sendable {
    /// The computed value on every output endpoint of every successful node.
    public let values: [OutputEndpoint: Quantity]
    /// The reason each failed node could not produce a value.
    public let errors: [NodeID: NodeError]

    init(values: [OutputEndpoint: Quantity], errors: [NodeID: NodeError]) {
        self.values = values
        self.errors = errors
    }

    /// The value on a node's first (or only) output port, if it computed one.
    public func value(of node: NodeID) -> Quantity? {
        values[OutputEndpoint(node)]
    }

    /// The value on a specific output endpoint, if it computed one.
    public func value(of endpoint: OutputEndpoint) -> Quantity? {
        values[endpoint]
    }

    /// Whether every node in the evaluated graph produced a value.
    public var isFullyResolved: Bool { errors.isEmpty }
}
