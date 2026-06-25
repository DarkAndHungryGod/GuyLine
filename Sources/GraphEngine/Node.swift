import QuantityKernel

/// A named input or output port on a node.
///
/// A port is the dimensioned connection point the vision describes: wires attach
/// to ports, and dimension checking ultimately happens in terms of the
/// ``Quantity`` values that flow through them.
public struct PortSpec: Equatable, Sendable {
    /// Short label shown next to the port, e.g. `"a"`, `"b"`, `"out"`.
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// The behaviour of a node: where its values come from and how it transforms
/// the values arriving on its input ports.
///
/// Crucially, an operation node does **not** declare a fixed output dimension.
/// The dimension is *derived* from the inputs at evaluation time (`m × m → m²`),
/// which is what lets the engine propagate units through the graph and catch the
/// "looks-right-but-the-units-are-wrong" mistakes the app exists to surface.
public enum NodeKind: Equatable, Sendable {
    /// A source node holding a literal value — the leaves of the dataflow.
    case input(Quantity)
    /// Adds `a + b`; throws if the operands' dimensions disagree.
    case add
    /// Subtracts `a − b`; throws if the operands' dimensions disagree.
    case subtract
    /// Multiplies `a × b`; dimensions combine and never conflict.
    case multiply
    /// Divides `a ÷ b`; dimensions combine and never conflict.
    case divide

    /// The input ports this kind exposes, in port-index order.
    public var inputs: [PortSpec] {
        switch self {
        case .input:
            return []
        case .add, .subtract, .multiply, .divide:
            return [PortSpec(name: "a"), PortSpec(name: "b")]
        }
    }

    /// The output ports this kind exposes, in port-index order.
    public var outputs: [PortSpec] {
        switch self {
        case .input, .add, .subtract, .multiply, .divide:
            return [PortSpec(name: "out")]
        }
    }

    /// Compute this node's output values from the values present on its input
    /// ports (already gathered in port-index order).
    ///
    /// - Throws: ``KernelError`` when an operation is dimensionally invalid
    ///   (adding a length to a mass, etc.). The evaluator turns the throw into a
    ///   per-node error rather than letting it escape.
    func evaluate(inputs: [Quantity]) throws -> [Quantity] {
        switch self {
        case .input(let quantity):
            return [quantity]
        case .add:
            return [try inputs[0] + inputs[1]]
        case .subtract:
            return [try inputs[0] - inputs[1]]
        case .multiply:
            return [inputs[0] * inputs[1]]
        case .divide:
            return [inputs[0] / inputs[1]]
        }
    }

    /// A default human-readable label for nodes that aren't given an explicit name.
    var defaultName: String {
        switch self {
        case .input: return "Input"
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .divide: return "Divide"
        }
    }
}

/// A single component in the graph: an identity, its behaviour, and a label.
public struct Node: Identifiable, Equatable, Sendable {
    public let id: NodeID
    public var kind: NodeKind
    public var name: String

    init(id: NodeID, kind: NodeKind, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }

    /// The node's input ports, in index order.
    public var inputs: [PortSpec] { kind.inputs }

    /// The node's output ports, in index order.
    public var outputs: [PortSpec] { kind.outputs }
}
