import SwiftUI
import GraphEngine

/// One node box on the canvas: a header (drag handle), its input/output ports,
/// and a footer showing the live value or error.
struct NodeView: View {
    let node: Node
    let position: CGPoint
    let isSelected: Bool
    let valueText: String?
    let dimensionText: String?
    let errorText: String?
    /// The input port currently targeted by a wire drag, if it belongs to this node.
    let activeDropTarget: InputEndpoint?

    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    let onBeginWire: (OutputEndpoint) -> Void
    let onUpdateWire: (CGPoint) -> Void
    let onEndWire: (CGPoint) -> Void
    let onDisconnectInput: (InputEndpoint) -> Void

    @State private var dragBase: CGPoint?

    private var hasError: Bool { errorText != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ports
            footer
        }
        .padding(10)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(radius: isSelected ? 6 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // The whole node body is a drag handle; ports use higher-priority
        // gestures so dragging *from a port* draws a wire instead of moving.
        .gesture(moveGesture)
        .onTapGesture(perform: onSelect)
    }

    /// Drag the node around the canvas. Records the start position once, then
    /// tracks the gesture's cumulative translation so motion never compounds.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(CanvasView.space))
            .onChanged { value in
                if dragBase == nil {
                    dragBase = position
                    onSelect()
                }
                let base = dragBase ?? position
                onMove(CGPoint(x: base.x + value.translation.width,
                               y: base.y + value.translation.height))
            }
            .onEnded { _ in dragBase = nil }
    }

    private var borderColor: Color {
        if hasError { return .red }
        if isSelected { return .accentColor }
        return Color.secondary.opacity(0.4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(node.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Text(kindLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    private var kindLabel: String {
        switch node.kind {
        case .input(let q): return q.isDimensionless ? "N" : "IN"
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        }
    }

    // MARK: - Ports

    private var ports: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(node.inputs.enumerated()), id: \.offset) { index, port in
                    let endpoint = InputEndpoint(node.id, index)
                    HStack(spacing: 5) {
                        PortDot(anchor: .input(endpoint), filled: false,
                                highlighted: activeDropTarget == endpoint)
                            .padding(5)
                            .contentShape(Circle())
                            .highPriorityGesture(
                                TapGesture().onEnded { onDisconnectInput(endpoint) }
                            )
                            .padding(-5)
                        Text(port.name).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(node.outputs.enumerated()), id: \.offset) { index, port in
                    let endpoint = OutputEndpoint(node.id, index)
                    HStack(spacing: 5) {
                        Text(port.name).font(.system(size: 11)).foregroundStyle(.secondary)
                        PortDot(anchor: .output(endpoint), filled: true)
                            .padding(5)
                            .contentShape(Circle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named(CanvasView.space))
                                    .onChanged { value in
                                        onBeginWire(endpoint)
                                        onUpdateWire(value.location)
                                    }
                                    .onEnded { value in onEndWire(value.location) }
                            )
                            .padding(-5)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let valueText {
            VStack(alignment: .leading, spacing: 1) {
                Text(valueText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                if let dimensionText {
                    Text(dimensionText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small circular port terminal that reports its centre in canvas coordinates.
/// When `highlighted`, it grows and fills to signal it's the active drop target.
struct PortDot: View {
    let anchor: PortAnchor
    let filled: Bool
    var highlighted: Bool = false

    var body: some View {
        Circle()
            .fill(filled || highlighted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .overlay {
                // A halo ring that appears only while this port is the drop target.
                if highlighted {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 3)
                        .frame(width: 20, height: 20)
                }
            }
            .scaleEffect(highlighted ? 1.25 : 1)
            .animation(.easeOut(duration: 0.12), value: highlighted)
            .background(
                GeometryReader { geo in
                    let frame = geo.frame(in: .named(CanvasView.space))
                    Color.clear.preference(
                        key: PortAnchorKey.self,
                        value: [anchor: CGPoint(x: frame.midX, y: frame.midY)]
                    )
                }
            )
            .contentShape(Circle())
    }
}
