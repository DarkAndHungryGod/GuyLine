import QuantityKernel

/// The canonical, serializable representation of a ``Graph``.
///
/// This is the language-neutral contract the macOS UI, the AI agent layer, and
/// any future cross-language binding all share (see `docs/design/engine-interface.md`).
/// It is deliberately *not* the in-memory `Graph`: nodes are addressed by stable,
/// author-chosen **string ids** (not `UUID`s), units travel as **symbol strings**,
/// ports are named, and there is no UI/layout state. Loading resolves all of that
/// against a ``UnitCatalog`` and hands back an ``IdMap`` so a later save can reuse
/// the same ids.
public struct GraphDocument: Codable, Equatable, Sendable {
    /// The schema this document was written against. Loading rejects versions it
    /// does not understand rather than silently misreading them.
    public var schemaVersion: Int
    public var nodes: [NodeDocument]
    public var edges: [EdgeDocument]

    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = GraphDocument.currentSchemaVersion,
        nodes: [NodeDocument],
        edges: [EdgeDocument]
    ) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes
        self.edges = edges
    }
}

/// One node in a ``GraphDocument``. `value`/`unit` are present only for `input`
/// nodes; operation nodes (`add`, `multiply`, …) carry neither.
public struct NodeDocument: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var name: String?
    public var value: Double?
    public var unit: String?

    public init(
        id: String,
        kind: String,
        name: String? = nil,
        value: Double? = nil,
        unit: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.value = value
        self.unit = unit
    }
}

/// A reference to one port of one node, by string id. `port` is omitted to mean
/// the node's default port (the sole output, or the first input). It encodes as a
/// bare string when the port is defaulted (`"area"`) and as an object otherwise
/// (`{"node":"total","port":"a"}`).
public struct EndpointRef: Codable, Equatable, Sendable {
    public var node: String
    public var port: String?

    public init(node: String, port: String? = nil) {
        self.node = node
        self.port = port
    }

    public init(from decoder: Decoder) throws {
        // Bare-string form: just the node id, default port.
        if let single = try? decoder.singleValueContainer(),
           let id = try? single.decode(String.self) {
            self.node = id
            self.port = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.node = try container.decode(String.self, forKey: .node)
        self.port = try container.decodeIfPresent(String.self, forKey: .port)
    }

    public func encode(to encoder: Encoder) throws {
        if let port {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(node, forKey: .node)
            try container.encode(port, forKey: .port)
        } else {
            var single = encoder.singleValueContainer()
            try single.encode(node)
        }
    }

    private enum CodingKeys: String, CodingKey { case node, port }
}

/// A wire in a ``GraphDocument``: from a source node's output to a target node's
/// input.
public struct EdgeDocument: Codable, Equatable, Sendable {
    public var from: EndpointRef
    public var to: EndpointRef

    public init(from: EndpointRef, to: EndpointRef) {
        self.from = from
        self.to = to
    }
}

/// The bidirectional mapping between a document's string ids and the in-memory
/// `NodeID`s a `Graph` uses. Returned by ``Graph/load(_:catalog:)`` and accepted
/// by ``Graph/document(using:)`` so that load → edit → save keeps stable ids.
public struct IdMap: Sendable {
    private(set) var byString: [String: NodeID]
    private(set) var byNode: [NodeID: String]

    init() {
        byString = [:]
        byNode = [:]
    }

    mutating func insert(_ string: String, _ node: NodeID) {
        byString[string] = node
        byNode[node] = string
    }

    public func nodeID(for string: String) -> NodeID? { byString[string] }
    public func string(for node: NodeID) -> String? { byNode[node] }
}

/// Why a ``GraphDocument`` could not be loaded into a `Graph`.
///
/// These are *structural* document problems, surfaced eagerly at load time —
/// distinct from the recoverable per-node `NodeError`s that only emerge during
/// ``Graph/evaluate()``.
public enum DocumentError: Error, Equatable, Sendable {
    /// The document's `schemaVersion` is not one this build understands.
    case unsupportedSchemaVersion(Int)
    /// Two nodes share the same string id.
    case duplicateNodeID(String)
    /// A node's `kind` string is not a known node kind.
    case unknownKind(node: String, kind: String)
    /// An `input` node is missing its `value` or `unit`.
    case missingInputValue(node: String)
    /// A node's unit symbol is not in the catalog.
    case unknownUnit(node: String, symbol: String)
    /// An edge references a node id that is not in the document.
    case unknownNode(String)
    /// An edge names a port the referenced node does not have.
    case unknownPort(node: String, port: String)
    /// The wire was structurally rejected by `Graph.connect` (e.g. the input is
    /// already wired).
    case connection(ConnectionError)
}

// MARK: - Load

extension Graph {
    /// Build a `Graph` from a ``GraphDocument``, resolving unit symbols against
    /// `catalog` and assigning fresh `NodeID`s.
    ///
    /// - Returns: the graph and an ``IdMap`` tying each document id to its new
    ///   `NodeID`.
    /// - Throws: ``DocumentError`` for any structural problem (unknown kind/unit,
    ///   duplicate id, dangling or malformed edge).
    public static func load(
        _ document: GraphDocument,
        catalog: UnitCatalog
    ) throws -> (graph: Graph, ids: IdMap) {
        guard document.schemaVersion == GraphDocument.currentSchemaVersion else {
            throw DocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }

        var graph = Graph()
        var ids = IdMap()

        for node in document.nodes {
            guard ids.nodeID(for: node.id) == nil else {
                throw DocumentError.duplicateNodeID(node.id)
            }
            let kind = try nodeKind(from: node, catalog: catalog)
            let nodeID = graph.addNode(kind, name: node.name ?? node.id)
            ids.insert(node.id, nodeID)
        }

        for edge in document.edges {
            guard let sourceID = ids.nodeID(for: edge.from.node) else {
                throw DocumentError.unknownNode(edge.from.node)
            }
            guard let targetID = ids.nodeID(for: edge.to.node) else {
                throw DocumentError.unknownNode(edge.to.node)
            }
            // Force-unwrap is safe: we just inserted these ids above.
            let sourceKind = graph.nodes[sourceID]!.kind
            let targetKind = graph.nodes[targetID]!.kind

            let outPort = try outputIndex(edge.from.port, in: sourceKind, node: edge.from.node)
            let inPort = try inputIndex(edge.to.port, in: targetKind, node: edge.to.node)

            do {
                try graph.connect(OutputEndpoint(sourceID, outPort), to: InputEndpoint(targetID, inPort))
            } catch let error as ConnectionError {
                throw DocumentError.connection(error)
            }
        }

        return (graph, ids)
    }

    private static func nodeKind(from node: NodeDocument, catalog: UnitCatalog) throws -> NodeKind {
        switch node.kind {
        case "input":
            guard let value = node.value, let symbol = node.unit else {
                throw DocumentError.missingInputValue(node: node.id)
            }
            let unit: Unit
            do {
                unit = try catalog.unit(symbol)
            } catch {
                throw DocumentError.unknownUnit(node: node.id, symbol: symbol)
            }
            return .input(Quantity(value: value, unit: unit))
        case "add": return .add
        case "subtract": return .subtract
        case "multiply": return .multiply
        case "divide": return .divide
        default:
            throw DocumentError.unknownKind(node: node.id, kind: node.kind)
        }
    }

    private static func outputIndex(_ name: String?, in kind: NodeKind, node: String) throws -> Int {
        guard let name else { return 0 }
        guard let index = kind.outputs.firstIndex(where: { $0.name == name }) else {
            throw DocumentError.unknownPort(node: node, port: name)
        }
        return index
    }

    private static func inputIndex(_ name: String?, in kind: NodeKind, node: String) throws -> Int {
        guard let name else { return 0 }
        guard let index = kind.inputs.firstIndex(where: { $0.name == name }) else {
            throw DocumentError.unknownPort(node: node, port: name)
        }
        return index
    }
}

// MARK: - Save

extension Graph {
    /// Serialize this graph to a ``GraphDocument``.
    ///
    /// Nodes present in `ids` reuse their original string id; any node without one
    /// (e.g. added in code after a load) is given a fresh readable id derived from
    /// its name. Output is deterministic: nodes are sorted by id and edges by
    /// their endpoints, so the same graph always serializes identically.
    public func document(using ids: IdMap? = nil) -> GraphDocument {
        var assigned: [NodeID: String] = [:]
        var used: Set<String> = []

        // First pass: honour ids carried over from a load.
        if let ids {
            for id in nodes.keys {
                if let string = ids.string(for: id) {
                    assigned[id] = string
                    used.insert(string)
                }
            }
        }
        // Second pass: mint readable ids for anything still unassigned. Sorted by
        // NodeID so generation is deterministic across runs.
        for id in nodes.keys.sorted(by: { $0.description < $1.description })
        where assigned[id] == nil {
            let string = Self.uniqueID(base: slug(nodes[id]!.name), used: used)
            assigned[id] = string
            used.insert(string)
        }

        let nodeDocs = nodes.values
            .map { node -> NodeDocument in
                let stringID = assigned[node.id]!
                switch node.kind {
                case .input(let quantity):
                    return NodeDocument(
                        id: stringID, kind: "input", name: node.name,
                        value: quantity.value, unit: quantity.unit.symbol
                    )
                case .add, .subtract, .multiply, .divide:
                    return NodeDocument(id: stringID, kind: kindTag(node.kind), name: node.name)
                }
            }
            .sorted { $0.id < $1.id }

        let edgeDocs = edges
            .map { edge -> EdgeDocument in
                let sourceNode = nodes[edge.source.node]!
                let targetNode = nodes[edge.target.node]!
                // Omit the source port when it is the sole/default output.
                let outName = sourceNode.outputs.count > 1
                    ? sourceNode.outputs[edge.source.port].name : nil
                let inName = targetNode.inputs[edge.target.port].name
                return EdgeDocument(
                    from: EndpointRef(node: assigned[edge.source.node]!, port: outName),
                    to: EndpointRef(node: assigned[edge.target.node]!, port: inName)
                )
            }
            .sorted {
                ($0.from.node, $0.to.node, $0.to.port ?? "") < ($1.from.node, $1.to.node, $1.to.port ?? "")
            }

        return GraphDocument(nodes: nodeDocs, edges: edgeDocs)
    }

    private func kindTag(_ kind: NodeKind) -> String {
        switch kind {
        case .input: return "input"
        case .add: return "add"
        case .subtract: return "subtract"
        case .multiply: return "multiply"
        case .divide: return "divide"
        }
    }

    /// A lowercase, underscore-joined id derived from a node's name; falls back to
    /// `"node"` when the name has no usable characters.
    private func slug(_ name: String) -> String {
        let allowed = name.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        let parts = String(allowed).split(separator: " ")
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? "node" : joined
    }

    private static func uniqueID(base: String, used: Set<String>) -> String {
        guard used.contains(base) else { return base }
        var n = 2
        while used.contains("\(base)_\(n)") { n += 1 }
        return "\(base)_\(n)"
    }
}
