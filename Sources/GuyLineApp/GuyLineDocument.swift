import SwiftUI
import UniformTypeIdentifiers
import GraphEngine

extension UTType {
    /// GuyLine's document type: a JSON file (so it's inspectable and the engine /
    /// AI layer can read the `document` half with a plain JSON decode) carrying a
    /// ``GraphFile`` envelope.
    ///
    /// Declared `exportedAs` because GuyLine owns the type. Full Finder/Launch
    /// Services association (double-click to open, the `.guyline` badge) also needs
    /// the matching `UTExportedTypeDeclarations`/`CFBundleDocumentTypes` in an app
    /// bundle's Info.plist — not present when running the SPM executable via
    /// `swift run`, but in-app Open/Save work regardless.
    static let guyLineGraph = UTType(exportedAs: "com.guyline.graph", conformingTo: .json)
}

/// A node's saved canvas position. A neutral `{ "x":…, "y":… }` rather than the
/// platform `CGPoint` so the on-disk presentation stays portable and the JSON is
/// self-describing.
struct CanvasPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// The macOS canvas's presentation layer — everything the front-end persists that
/// the engine and AI layer deliberately don't (see `docs/design/document-based-app.md`).
///
/// Positions and the selection are keyed by the **document's stable string ids**,
/// not the in-memory `NodeID`s, so they survive a save → load round-trip and stay
/// meaningful to any tool that opens the same file. A correctness-only consumer
/// ignores this whole half.
struct CanvasPresentation: Codable, Equatable, Sendable {
    var positions: [String: CanvasPoint]
    var selection: String?

    init(positions: [String: CanvasPoint] = [:], selection: String? = nil) {
        self.positions = positions
        self.selection = selection
    }
}

/// A GuyLine graph as a document. A `ReferenceFileDocument` because the editable
/// state lives in a reference-type ``GraphViewModel`` (an `ObservableObject` the
/// canvas observes); the value-type `snapshot` decouples the main-actor model from
/// the background write, and is the seam undo/autosave hook into later.
@MainActor
final class GuyLineDocument: @preconcurrency ReferenceFileDocument {
    typealias Snapshot = GraphFile<CanvasPresentation>

    nonisolated static var readableContentTypes: [UTType] { [.guyLineGraph] }

    let viewModel: GraphViewModel

    /// A new, empty untitled document.
    init() {
        self.viewModel = GraphViewModel()
    }

    /// An untitled document seeded from a graph (used by "New from Example"): the
    /// graph's semantics with no saved layout, so the canvas auto-lays it out.
    init(document: GraphDocument) {
        self.viewModel = (try? GraphViewModel(file: GraphFile(document: document)))
            ?? GraphViewModel()
    }

    /// Open an existing document from disk.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let file = try GraphFile<CanvasPresentation>.decoded(from: data)
        self.viewModel = try GraphViewModel(file: file)
    }

    /// Capture the current state as a value the writer can serialize. The snapshot
    /// is `Sendable`, so `fileWrapper` (nonisolated) can run the encode without
    /// touching the main-actor model — the seam undo/autosave hook into later.
    func snapshot(contentType: UTType) throws -> Snapshot {
        viewModel.fileSnapshot()
    }

    nonisolated func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }
}
