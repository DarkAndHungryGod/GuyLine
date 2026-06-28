import SwiftUI
import AppKit
import GraphEngine

@main
struct GuyLineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        DocumentGroup(newDocument: { MainActor.assumeIsolated { GuyLineDocument() } }) { configuration in
            ContentView(vm: configuration.document.viewModel)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            ExampleCommands()
        }
    }
}

/// Adds "New from Example" under the File menu's New group: each bundled example
/// opens as its own untitled document rather than overwriting the current graph.
private struct ExampleCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("New from Example") {
                ForEach(BundledExamples.all) { example in
                    Button(example.title) {
                        // The factory runs on the main actor when SwiftUI creates
                        // the document window; assert it so the main-actor init is
                        // reachable from this nonisolated closure.
                        newDocument {
                            MainActor.assumeIsolated { GuyLineDocument(document: example.document) }
                        }
                    }
                    .help(example.summary)
                }
            }
        }
    }
}

/// Forces a normal foreground app when launched via `swift run` (which otherwise
/// starts as a background accessory, leaving the window behind other apps).
///
/// Deliberately does **not** implement `applicationShouldTerminateAfterLastWindowClosed`:
/// for a document app the standard behaviour (and the only one that works with
/// `DocumentGroup`'s launch open-panel) is to stay alive when no window is open.
/// Returning `true` there quit the app the instant the open panel closed to make a
/// new document — before SwiftUI could create the document window — which looked
/// exactly like an instant crash on "New Document".
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
