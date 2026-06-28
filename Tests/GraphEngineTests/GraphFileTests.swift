import XCTest
import QuantityKernel
@testable import GraphEngine

/// Tests for the on-disk ``GraphFile`` envelope: the semantics/presentation split,
/// JSON round-trips with an opaque presentation payload, the correctness-only read
/// path that ignores presentation, format-version rejection, and the
/// ``Graph/documentAndIDs(using:)`` mapping a front-end needs to key presentation
/// by stable document ids.
final class GraphFileTests: XCTestCase {
    private let catalog = UnitCatalog.standard

    /// A stand-in for whatever layout a front-end stores. The engine treats
    /// presentation as opaque, so any `Codable` shape exercises the generic.
    private struct StubPresentation: Codable, Equatable, Sendable {
        var positions: [String: [Double]]
    }

    private var pricingDoc: GraphDocument {
        GraphDocument(
            nodes: [
                NodeDocument(id: "area", kind: "input", name: "Floor area", value: 50, unit: "m^2"),
                NodeDocument(id: "rate", kind: "input", name: "Unit rate", value: 30, unit: "$/m^2"),
                NodeDocument(id: "total", kind: "multiply", name: "Total cost")
            ],
            edges: [
                EdgeDocument(from: EndpointRef(node: "area"), to: EndpointRef(node: "total", port: "a")),
                EdgeDocument(from: EndpointRef(node: "rate"), to: EndpointRef(node: "total", port: "b"))
            ]
        )
    }

    // MARK: Envelope round-trips, presentation and all

    func testFileSurvivesJSONRoundTrip() throws {
        let file = GraphFile(
            document: pricingDoc,
            presentation: StubPresentation(positions: ["area": [10, 20], "total": [300, 40]])
        )
        let decoded = try GraphFile<StubPresentation>.decoded(from: try file.encoded())
        XCTAssertEqual(decoded, file)
    }

    func testEncodingIsDeterministic() throws {
        let file = GraphFile(
            document: pricingDoc,
            presentation: StubPresentation(positions: ["b": [1, 1], "a": [0, 0]])
        )
        XCTAssertEqual(try file.encoded(), try file.encoded())
    }

    func testPresentationIsOptional() throws {
        let file = GraphFile<StubPresentation>(document: pricingDoc)
        let decoded = try GraphFile<StubPresentation>.decoded(from: try file.encoded())
        XCTAssertNil(decoded.presentation)
        XCTAssertEqual(decoded.document, pricingDoc)
    }

    // MARK: Correctness-only consumers read just the document

    func testDocumentOnlyReadIgnoresPresentation() throws {
        let file = GraphFile(
            document: pricingDoc,
            presentation: StubPresentation(positions: ["area": [10, 20]])
        )
        // A consumer that knows nothing of `StubPresentation` still gets the graph.
        let view = try GraphFileDocument(from: try file.encoded())
        XCTAssertEqual(view.document, pricingDoc)
    }

    // MARK: Version gating

    func testUnsupportedFormatVersionIsRejected() throws {
        var file = GraphFile<StubPresentation>(document: pricingDoc)
        file.formatVersion = 999
        XCTAssertThrowsError(try GraphFile<StubPresentation>.decoded(from: try file.encoded())) { error in
            XCTAssertEqual(error as? GraphFileError, .unsupportedFormatVersion(999))
        }
    }

    // MARK: documentAndIDs exposes the full id mapping

    func testDocumentAndIDsAgreesWithDocument() throws {
        let (graph, ids) = try Graph.load(pricingDoc, catalog: catalog)
        let pair = graph.documentAndIDs(using: ids)
        XCTAssertEqual(pair.document, graph.document(using: ids))
    }

    func testDocumentAndIDsMapsEveryNodeIncludingMinted() throws {
        var graph = Graph()
        let width = graph.addInput(try catalog.quantity(2, "m"), name: "width")
        let height = graph.addInput(try catalog.quantity(3, "m"), name: "height")

        // No incoming map: every id is freshly minted, and the returned map must
        // still cover both nodes so a caller can translate its NodeIDs.
        let (document, ids) = graph.documentAndIDs()
        XCTAssertEqual(Set(document.nodes.map(\.id)), ["width", "height"])
        XCTAssertEqual(ids.string(for: width), "width")
        XCTAssertEqual(ids.string(for: height), "height")
        XCTAssertEqual(ids.nodeID(for: "width"), width)
    }
}
