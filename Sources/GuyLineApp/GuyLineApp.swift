import SwiftUI
import AppKit
import GraphEngine

@main
struct GuyLineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var vm = GraphViewModel.demo()

    var body: some Scene {
        WindowGroup("GuyLine") {
            ContentView(vm: vm)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.titleBar)
    }
}

/// Forces a normal foreground app when launched via `swift run` (which otherwise
/// starts as a background accessory, leaving the window behind other apps).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Top-level layout: a palette toolbar over the canvas + inspector split.
struct ContentView: View {
    @ObservedObject var vm: GraphViewModel

    var body: some View {
        VStack(spacing: 0) {
            PaletteBar(vm: vm)
            Divider()
            HStack(spacing: 0) {
                CanvasView(vm: vm)
                Divider()
                InspectorPanel(vm: vm)
                    .frame(width: 270)
            }
        }
    }
}

/// The node palette: buttons that drop a new node onto the canvas.
private struct PaletteBar: View {
    @ObservedObject var vm: GraphViewModel
    @State private var dropCount = 0

    var body: some View {
        HStack(spacing: 8) {
            Text("Add:").foregroundStyle(.secondary)
            button("Input", systemImage: "ruler") { vm.addInputNode(at: nextDropPoint()) }
            button("Number", systemImage: "number") { vm.addNumberNode(at: nextDropPoint()) }
            button("Add", systemImage: "plus") { add(.add) }
            button("Subtract", systemImage: "minus") { add(.subtract) }
            button("Multiply", systemImage: "multiply") { add(.multiply) }
            button("Divide", systemImage: "divide") { add(.divide) }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBadge: some View {
        let errorCount = vm.result.errors.count
        return Label(
            errorCount == 0 ? "All nodes resolve" : "\(errorCount) node\(errorCount == 1 ? "" : "s") with errors",
            systemImage: errorCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(errorCount == 0 ? .green : .red)
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func add(_ kind: NodeKind) {
        vm.addNode(kind, at: nextDropPoint())
    }

    /// Cascade new nodes so they don't stack exactly on top of each other.
    private func nextDropPoint() -> CGPoint {
        defer { dropCount += 1 }
        let step = CGFloat(dropCount % 6)
        return CGPoint(x: 300 + step * 26, y: 160 + step * 26)
    }
}
