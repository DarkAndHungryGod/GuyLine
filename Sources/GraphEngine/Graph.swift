import QuantityKernel

/// Why a `connect` attempt was rejected outright.
///
/// These are structural problems with the wire itself (does the port exist? is
/// the input already taken?), distinct from the *dimensional* problems that only
/// emerge once values flow during ``Graph/evaluate()``.
public enum ConnectionError: Error, Equatable, Sendable {
    /// The source or target node is not in the graph.
    case unknownNode(NodeID)
    /// The named port index does not exist on that node.
    case unknownPort
    /// The target input port already has a wire; inputs accept at most one.
    case inputAlreadyConnected(InputEndpoint)
}

/// A headless dataflow graph: nodes wired together at their ports.
///
/// `Graph` is a plain value type that holds structure only. Computing values —
/// and surfacing dimensional mistakes — is done by ``evaluate()``, which never
/// mutates the graph, so the same graph can be recomputed freely.
public struct Graph: Equatable, Sendable {
    private(set) public var nodes: [NodeID: Node] = [:]
    private(set) public var edges: [Edge] = []

    public init() {}

    // MARK: - Building

    /// Add a node of the given kind and return its fresh identity.
    /// - Parameter name: an optional label; defaults to the kind's name.
    @discardableResult
    public mutating func addNode(_ kind: NodeKind, name: String? = nil) -> NodeID {
        let id = NodeID()
        nodes[id] = Node(id: id, kind: kind, name: name ?? kind.defaultName)
        return id
    }

    /// Convenience: add an ``NodeKind/input(_:)`` source node holding `quantity`.
    @discardableResult
    public mutating func addInput(_ quantity: Quantity, name: String? = nil) -> NodeID {
        addNode(.input(quantity), name: name)
    }

    /// Wire an output endpoint to an input endpoint.
    ///
    /// - Throws: ``ConnectionError`` if either endpoint refers to a missing node
    ///   or port, or if the target input is already wired.
    public mutating func connect(_ source: OutputEndpoint, to target: InputEndpoint) throws {
        guard let sourceNode = nodes[source.node] else {
            throw ConnectionError.unknownNode(source.node)
        }
        guard let targetNode = nodes[target.node] else {
            throw ConnectionError.unknownNode(target.node)
        }
        guard source.port >= 0, source.port < sourceNode.outputs.count else {
            throw ConnectionError.unknownPort
        }
        guard target.port >= 0, target.port < targetNode.inputs.count else {
            throw ConnectionError.unknownPort
        }
        if edges.contains(where: { $0.target == target }) {
            throw ConnectionError.inputAlreadyConnected(target)
        }
        edges.append(Edge(source: source, target: target))
    }

    /// Replace a node's behaviour in place, keeping its identity and position in
    /// the graph. Used by the UI to edit an input node's value or retype a node.
    ///
    /// If the new kind has fewer ports than the old one, any wires attached to a
    /// now-missing port are dropped so the graph stays well-formed.
    /// - Returns: `false` if no node with that id exists.
    @discardableResult
    public mutating func updateNode(_ id: NodeID, kind: NodeKind) -> Bool {
        guard nodes[id] != nil else { return false }
        nodes[id]?.kind = kind
        let inputCount = kind.inputs.count
        let outputCount = kind.outputs.count
        edges.removeAll { edge in
            (edge.target.node == id && edge.target.port >= inputCount)
                || (edge.source.node == id && edge.source.port >= outputCount)
        }
        return true
    }

    /// Mark a node's output as a discrete (whole-unit) quantity, or clear that
    /// mark. See ``Node/quantized``; the value is rounded up during evaluation.
    /// - Returns: `false` if no node with that id exists.
    @discardableResult
    public mutating func setQuantized(_ id: NodeID, _ quantized: Bool) -> Bool {
        guard nodes[id] != nil else { return false }
        nodes[id]?.quantized = quantized
        return true
    }

    /// Rename a node, keeping its identity, wiring, and behaviour.
    /// - Returns: `false` if no node with that id exists.
    @discardableResult
    public mutating func renameNode(_ id: NodeID, to name: String) -> Bool {
        guard nodes[id] != nil else { return false }
        nodes[id]?.name = name
        return true
    }

    /// Remove the wire feeding `target`, if any.
    public mutating func disconnect(_ target: InputEndpoint) {
        edges.removeAll { $0.target == target }
    }

    /// Remove a node and every wire touching it.
    public mutating func removeNode(_ id: NodeID) {
        nodes[id] = nil
        edges.removeAll { $0.source.node == id || $0.target.node == id }
    }
}

/// A wire from one node's output port to another node's input port.
public struct Edge: Hashable, Sendable {
    public let source: OutputEndpoint
    public let target: InputEndpoint

    public init(source: OutputEndpoint, target: InputEndpoint) {
        self.source = source
        self.target = target
    }
}
