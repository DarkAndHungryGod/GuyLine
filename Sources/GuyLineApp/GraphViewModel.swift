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

    // MARK: - Loading documents

    /// Replace the current graph with a loaded ``GraphDocument`` (e.g. a bundled
    /// example), laying it out automatically since the document carries no
    /// positions. Silently keeps the existing graph if the document can't load —
    /// the bundled examples are test-verified, so a failure here is not expected.
    func load(_ document: GraphDocument) {
        guard let (loaded, _) = try? Graph.load(document, catalog: catalog) else { return }
        graph = loaded
        positions = Self.autoLayout(loaded)
        selection = nil
        recompute()
    }

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

    // MARK: - Demo seed

    /// A small starting graph — the concrete-pour estimating example — so the
    /// canvas isn't empty on first launch:
    ///   24 m³ per pile × $200/m³ = $4800/pile, × 5 piles = $24000.
    /// The "5 piles" node is a dimensionless number that scales the dollars.
    static func demo() -> GraphViewModel {
        let vm = GraphViewModel()
        let catalog = UnitCatalog.standard
        let cubicMeter = try! catalog.unit("m").power(3)
        let dollar = try! catalog.unit("$")

        let rate = vm.graph.addNode(.input(Quantity(value: 200, unit: dollar / cubicMeter)), name: "rate")
        let pour = vm.graph.addNode(.input(Quantity(value: 24, unit: cubicMeter)), name: "pour / pile")
        let perPile = vm.graph.addNode(.multiply, name: "cost / pile")
        let piles = vm.graph.addNode(.input(Quantity(scalar: 5)), name: "piles")
        let total = vm.graph.addNode(.multiply, name: "total")

        try? vm.graph.connect(OutputEndpoint(rate), to: InputEndpoint(perPile, 0))
        try? vm.graph.connect(OutputEndpoint(pour), to: InputEndpoint(perPile, 1))
        try? vm.graph.connect(OutputEndpoint(perPile), to: InputEndpoint(total, 0))
        try? vm.graph.connect(OutputEndpoint(piles), to: InputEndpoint(total, 1))

        // Top-left corners in canvas space.
        vm.positions = [
            rate: CGPoint(x: 60, y: 60),
            pour: CGPoint(x: 60, y: 220),
            perPile: CGPoint(x: 340, y: 120),
            piles: CGPoint(x: 340, y: 300),
            total: CGPoint(x: 620, y: 200),
        ]
        vm.recompute()
        return vm
    }
}
