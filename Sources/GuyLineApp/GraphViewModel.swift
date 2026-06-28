import SwiftUI
import GraphEngine
import QuantityKernel

/// The bridge between the headless ``Graph`` and SwiftUI.
///
/// The engine stays UI-agnostic, so everything the canvas needs but the graph
/// deliberately doesn't store — node positions, the current selection, the live
/// evaluation result — lives here. Every structural edit funnels through a
/// mutating method that re-evaluates, so `result` is always in sync with `graph`.
@MainActor
final class GraphViewModel: ObservableObject {
    @Published private(set) var graph = Graph()
    @Published private(set) var result = Graph().evaluate()
    @Published var positions: [NodeID: CGPoint] = [:]
    @Published var selection: NodeID?

    private let catalog = UnitCatalog.standard

    /// Maps the document's stable string ids to the in-memory `NodeID`s, so a save
    /// reuses the same ids a load produced — and so presentation state (positions,
    /// selection) can be translated to and from the on-disk id space. Replaced on
    /// load and refreshed on every save (which may mint ids for newly added nodes).
    private var ids = IdMap()

    // MARK: - Lifecycle

    /// A new, empty document.
    init() {}

    /// Build from an opened ``GraphFile``: load the semantics, then restore saved
    /// node positions and selection. Auto-layout fills in any node the file didn't
    /// position (including the whole graph when there's no presentation at all),
    /// so the canvas is always legible.
    init(file: GraphFile<CanvasPresentation>) throws {
        let (loaded, ids) = try Graph.load(file.document, catalog: catalog)
        graph = loaded
        self.ids = ids

        var positions = Self.autoLayout(loaded)
        if let presentation = file.presentation {
            for (stringID, point) in presentation.positions {
                if let nodeID = ids.nodeID(for: stringID) { positions[nodeID] = point.cgPoint }
            }
        }
        self.positions = positions
        selection = file.presentation?.selection.flatMap { ids.nodeID(for: $0) }
        recompute()
    }

    /// Capture the current graph and canvas layout as a serializable file.
    ///
    /// Round-tripping through ``Graph/documentAndIDs(using:)`` reuses existing ids
    /// and mints stable ones for any node added since the last save; the refreshed
    /// map is kept so later saves stay stable. Presentation is keyed by those
    /// string ids, dropping any position whose node no longer exists.
    func fileSnapshot() -> GraphFile<CanvasPresentation> {
        let (document, ids) = graph.documentAndIDs(using: self.ids)
        self.ids = ids

        var savedPositions: [String: CanvasPoint] = [:]
        for (nodeID, point) in positions {
            if let stringID = ids.string(for: nodeID) {
                savedPositions[stringID] = CanvasPoint(point)
            }
        }
        let presentation = CanvasPresentation(
            positions: savedPositions,
            selection: selection.flatMap { ids.string(for: $0) }
        )
        return GraphFile(document: document, presentation: presentation)
    }

    /// Nodes in a stable order so the canvas doesn't reshuffle on recompute.
    var nodeList: [Node] {
        graph.nodes.values.sorted { $0.id.description < $1.id.description }
    }

    // MARK: - Editing

    @discardableResult
    func addNode(_ kind: NodeKind, at point: CGPoint) -> NodeID {
        let id = graph.addNode(kind)
        positions[id] = point
        recompute()
        selection = id
        return id
    }

    /// Add a fresh input node with a neutral, editable starting value so it
    /// resolves immediately and can be retyped in the inspector.
    func addInputNode(at point: CGPoint) {
        let quantity = (try? catalog.quantity(1, "m")) ?? Quantity(value: 1, unit: try! catalog.unit("m"))
        addNode(.input(quantity), at: point)
    }

    /// Add a dimensionless number node — a bare count (e.g. "5 piles") that
    /// carries no unit and scales whatever it feeds into a multiply.
    func addNumberNode(at point: CGPoint) {
        addNode(.input(Quantity(scalar: 1)), at: point)
    }

    func moveNode(_ id: NodeID, to point: CGPoint) {
        positions[id] = point
    }

    /// Rename a node. No recompute needed — a label change can't alter values.
    func rename(_ id: NodeID, to name: String) {
        graph.renameNode(id, to: name)
    }

    func connect(from source: OutputEndpoint, to target: InputEndpoint) {
        try? graph.connect(source, to: target)
        recompute()
    }

    func disconnect(_ target: InputEndpoint) {
        graph.disconnect(target)
        recompute()
    }

    func removeNode(_ id: NodeID) {
        graph.removeNode(id)
        positions[id] = nil
        if selection == id { selection = nil }
        recompute()
    }

    /// Apply an edited value/unit to an input node.
    /// - Returns: an error message to show in the inspector, or `nil` on success.
    func setInput(_ id: NodeID, valueText: String, symbol: String) -> String? {
        guard let value = Double(valueText) else {
            return "“\(valueText)” isn’t a number"
        }
        do {
            let unit = try catalog.unit(symbol)
            graph.updateNode(id, kind: .input(Quantity(value: value, unit: unit)))
            recompute()
            return nil
        } catch {
            return "Unknown unit “\(symbol)”"
        }
    }

    private func recompute() {
        result = graph.evaluate()
    }

    // MARK: - Layout

    /// A simple layered layout: a node's column is the longest dependency path
    /// reaching it (sources at column 0), and nodes are stacked top-to-bottom
    /// within each column in a stable order. Good enough to make a loaded graph
    /// legible without overlapping; the user can rearrange from there.
    private static func autoLayout(_ graph: Graph) -> [NodeID: CGPoint] {
        let columnWidth: CGFloat = 260
        let rowHeight: CGFloat = 150
        let origin = CGPoint(x: 60, y: 40)

        // Incoming sources per node, for longest-path depth.
        var sources: [NodeID: [NodeID]] = [:]
        for edge in graph.edges {
            sources[edge.target.node, default: []].append(edge.source.node)
        }

        var depthCache: [NodeID: Int] = [:]
        func depth(_ id: NodeID, _ visiting: Set<NodeID>) -> Int {
            if let cached = depthCache[id] { return cached }
            // A node caught in a cycle resolves to column 0 rather than looping.
            guard !visiting.contains(id) else { return 0 }
            let incoming = sources[id] ?? []
            let value = incoming.isEmpty
                ? 0
                : (incoming.map { depth($0, visiting.union([id])) }.max() ?? 0) + 1
            depthCache[id] = value
            return value
        }

        // Group nodes by column, ordered stably so layout is deterministic.
        var columns: [Int: [NodeID]] = [:]
        for id in graph.nodes.keys.sorted(by: { $0.description < $1.description }) {
            columns[depth(id, [])] = (columns[depth(id, [])] ?? []) + [id]
        }

        var positions: [NodeID: CGPoint] = [:]
        for (column, ids) in columns {
            for (row, id) in ids.enumerated() {
                positions[id] = CGPoint(
                    x: origin.x + CGFloat(column) * columnWidth,
                    y: origin.y + CGFloat(row) * rowHeight
                )
            }
        }
        return positions
    }

    // MARK: - Display helpers

    /// The current value flowing out of a node's first output port, if it
    /// computed one, formatted as `"<value> <unit>"`.
    func valueText(for id: NodeID) -> String? {
        guard let q = result.value(of: id) else { return nil }
        if q.isDimensionless { return format(q.value) }
        return "\(format(q.value)) \(q.unit.symbol)"
    }

    /// The dimension of a node's output (e.g. `"Money"`, `"Length^3"`), or
    /// `nil` for a dimensionless number (nothing useful to caption).
    func dimensionText(for id: NodeID) -> String? {
        guard let q = result.value(of: id), !q.isDimensionless else { return nil }
        return q.unit.dimensionDescription
    }

    /// A human-readable reason a node failed, if it did.
    func errorText(for id: NodeID) -> String? {
        guard let error = result.errors[id], let node = graph.nodes[id] else { return nil }
        switch error {
        case .missingInput(let port):
            let name = port < node.inputs.count ? node.inputs[port].name : "\(port)"
            return "Input “\(name)” is not connected"
        case .upstreamFailure:
            return "Depends on a node that has an error"
        case .cycle:
            return "Part of a feedback loop"
        case .kernel(.incompatibleDimensions(let message)):
            return message
        case .kernel(.unknownUnit(let symbol)):
            return "Unknown unit “\(symbol)”"
        }
    }

    /// The raw input value/unit of an input node, for the inspector fields.
    func inputFields(for id: NodeID) -> (value: String, symbol: String)? {
        guard case .input(let q)? = graph.nodes[id]?.kind else { return nil }
        // A dimensionless number shows a blank unit field, not "none".
        return (format(q.value), q.isDimensionless ? "" : q.unit.symbol)
    }

    private func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
