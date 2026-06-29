import SwiftUI
import GraphEngine

/// The right-hand panel: details and editing for the selected node.
struct InspectorPanel: View {
    @ObservedObject var vm: GraphViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(12)
            Divider()
            if let id = vm.selection, let node = vm.graph.nodes[id] {
                NodeInspector(vm: vm, node: node)
                    .id(id) // reset editing state when the selection changes
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No selection").font(.headline)
                    Text("Select a node to inspect or edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Per-node detail view; input nodes get editable value/unit fields.
private struct NodeInspector: View {
    @ObservedObject var vm: GraphViewModel
    let node: Node

    @State private var nameText = ""
    @State private var valueText = ""
    @State private var symbolText = ""
    @State private var quantized = false
    @State private var editError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Name").foregroundStyle(.secondary)
                TextField("Name", text: $nameText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: nameText) { vm.rename(node.id, to: nameText) }
            }
            row("Kind", kindName)

            if isInput {
                Divider()
                Text("Value").font(.subheadline.weight(.semibold))
                TextField("Value", text: $valueText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(apply)
                HStack {
                    Text("Unit").font(.subheadline.weight(.semibold))
                    TextField("e.g. m, kg, $, $/m^3", text: $symbolText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(apply)
                }
                Button("Apply", action: apply)
                    .keyboardShortcut(.return, modifiers: [])
                if let editError {
                    Text(editError).font(.caption).foregroundStyle(.red)
                }
            }

            Divider()
            Toggle(isOn: $quantized) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quantized units")
                    Text("Round the result up to whole units (e.g. 201.6 → 202 bags).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: quantized) { vm.setQuantized(node.id, quantized) }

            Divider()
            Text("Result").font(.subheadline.weight(.semibold))
            if let error = vm.errorText(for: node.id) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            } else if let value = vm.valueText(for: node.id) {
                Text(value).font(.body.weight(.medium))
                if let dim = vm.dimensionText(for: node.id) {
                    Text(dim).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }

            Divider()
            Button(role: .destructive) {
                vm.removeNode(node.id)
            } label: {
                Label("Delete Node", systemImage: "trash")
            }
        }
        .padding(12)
        .onAppear(perform: loadFields)
    }

    private var isInput: Bool {
        if case .input = node.kind { return true }
        return false
    }

    private var kindName: String {
        switch node.kind {
        case .input: return "Input"
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .divide: return "Divide"
        }
    }

    private func loadFields() {
        nameText = node.name
        quantized = vm.isQuantized(node.id)
        if let fields = vm.inputFields(for: node.id) {
            valueText = fields.value
            symbolText = fields.symbol
        }
    }

    private func apply() {
        editError = vm.setInput(node.id, valueText: valueText, symbol: symbolText)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}
