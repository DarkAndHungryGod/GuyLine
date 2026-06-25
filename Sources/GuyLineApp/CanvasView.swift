import SwiftUI
import GraphEngine

/// Identifies one port on the canvas so its on-screen position can be collected
/// for wire drawing and drop hit-testing.
enum PortAnchor: Hashable {
    case input(InputEndpoint)
    case output(OutputEndpoint)
}

/// Collects every port's centre (in canvas coordinates) as the layout resolves.
struct PortAnchorKey: PreferenceKey {
    static let defaultValue: [PortAnchor: CGPoint] = [:]
    static func reduce(value: inout [PortAnchor: CGPoint], nextValue: () -> [PortAnchor: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// A wire being dragged out of an output port toward the cursor.
struct PendingWire {
    let from: OutputEndpoint
    var location: CGPoint
}

/// The graph canvas: wires underneath, nodes on top, with drag-to-connect.
struct CanvasView: View {
    @ObservedObject var vm: GraphViewModel

    @State private var anchors: [PortAnchor: CGPoint] = [:]
    @State private var pending: PendingWire?
    /// The input port a dragged wire would snap to right now, highlighted as a target.
    @State private var dropTarget: InputEndpoint?

    /// How close a dropped wire must land to an input port to connect.
    private let dropRadius: CGFloat = 22

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .underPageBackgroundColor)
                .contentShape(Rectangle())
                .onTapGesture { vm.selection = nil }

            wires
            nodes
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: CanvasView.space)
        .onPreferenceChange(PortAnchorKey.self) { anchors = $0 }
        .clipped()
    }

    static let space = "canvas"

    // MARK: - Wires

    private var wires: some View {
        ZStack {
            ForEach(vm.graph.edges, id: \.self) { edge in
                if let a = anchors[.output(edge.source)], let b = anchors[.input(edge.target)] {
                    let errored = vm.errorText(for: edge.target.node) != nil
                    WireShape(from: a, to: b)
                        .stroke(errored ? Color.red : Color.secondary,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    // Wider invisible hit area so the thin wire is clickable to delete.
                    WireShape(from: a, to: b)
                        .stroke(Color.black.opacity(0.001), lineWidth: 12)
                        .onTapGesture { vm.disconnect(edge.target) }
                }
            }
            if let pending, let a = anchors[.output(pending.from)] {
                WireShape(from: a, to: pending.location)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
            }
        }
    }

    // MARK: - Nodes

    private var nodes: some View {
        ForEach(vm.nodeList) { node in
            NodeView(
                node: node,
                position: vm.positions[node.id] ?? .zero,
                isSelected: vm.selection == node.id,
                valueText: vm.valueText(for: node.id),
                dimensionText: vm.dimensionText(for: node.id),
                errorText: vm.errorText(for: node.id),
                activeDropTarget: dropTarget,
                onSelect: { vm.selection = node.id },
                onMove: { vm.moveNode(node.id, to: $0) },
                onBeginWire: { pending = PendingWire(from: $0, location: anchors[.output($0)] ?? .zero) },
                onUpdateWire: { updateWire(to: $0) },
                onEndWire: { endWire(at: $0) },
                onDisconnectInput: { vm.disconnect($0) }
            )
            // Offset (not .position) so each node keeps its own intrinsic size
            // and hit region instead of expanding to fill the canvas. The stored
            // point is the node's top-left corner in canvas space.
            .offset(x: vm.positions[node.id]?.x ?? 0, y: vm.positions[node.id]?.y ?? 0)
        }
    }

    /// While dragging: move the wire end and light up the input it would snap to.
    private func updateWire(to location: CGPoint) {
        pending?.location = location
        dropTarget = nearestInput(to: location)
    }

    /// On release: connect to the snapped input, if any, and clear drag state.
    private func endWire(at location: CGPoint) {
        defer { pending = nil; dropTarget = nil }
        guard let from = pending?.from, let target = nearestInput(to: location) else { return }
        vm.connect(from: from, to: target)
    }

    /// The input port closest to `location` within the drop radius, excluding
    /// ports on the wire's own source node (no self-wiring).
    private func nearestInput(to location: CGPoint) -> InputEndpoint? {
        guard let from = pending?.from else { return nil }
        return anchors
            .compactMap { key, point -> (InputEndpoint, CGFloat)? in
                guard case .input(let endpoint) = key, endpoint.node != from.node else { return nil }
                return (endpoint, hypot(point.x - location.x, point.y - location.y))
            }
            .filter { $0.1 <= dropRadius }
            .min { $0.1 < $1.1 }?
            .0
    }
}

/// A left-to-right cubic curve between two points, like a node-editor wire.
struct WireShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = max(40, abs(to.x - from.x) * 0.5)
        path.move(to: from)
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x + dx, y: from.y),
            control2: CGPoint(x: to.x - dx, y: to.y)
        )
        return path
    }
}
