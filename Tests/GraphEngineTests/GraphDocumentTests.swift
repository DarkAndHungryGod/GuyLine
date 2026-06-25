import XCTest
import QuantityKernel
@testable import GraphEngine

/// Tests for the serializable ``GraphDocument`` contract: JSON round-trips, the
/// document → `Graph` → document round-trip (stable ids, deterministic output),
/// semantic correctness (a loaded graph still evaluates to the right unit), and
/// the structural load errors a document author needs surfaced.
final class GraphDocumentTests: XCTestCase {
    private let catalog = UnitCatalog.standard

    /// The flagship concrete-pricing graph, already in canonical (sorted) form so
    /// it equals its own re-serialization.
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

    // MARK: JSON is faithful

    func testDocumentSurvivesJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(pricingDoc)
        let decoded = try JSONDecoder().decode(GraphDocument.self, from: data)
        XCTAssertEqual(decoded, pricingDoc)
    }

    func testEndpointEncodesBareStringWhenDefaultedAndObjectOtherwise() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes

        let bare = try encoder.encode(EndpointRef(node: "area"))
        XCTAssertEqual(String(decoding: bare, as: UTF8.self), "\"area\"")

        let object = try encoder.encode(EndpointRef(node: "total", port: "a"))
        let decoded = try JSONDecoder().decode(EndpointRef.self, from: object)
        XCTAssertEqual(decoded, EndpointRef(node: "total", port: "a"))
    }

    // MARK: Load produces a graph that evaluates correctly

    func testLoadedGraphEvaluatesToDollars() throws {
        let (graph, ids) = try Graph.load(pricingDoc, catalog: catalog)
        let total = try XCTUnwrap(ids.nodeID(for: "total"))

        let out = try XCTUnwrap(graph.evaluate().value(of: total))
        XCTAssertEqual(out.value, 1500, accuracy: 1e-9)
        XCTAssertEqual(out.unit.dimensionDescription, "Money")
    }

    // MARK: document → Graph → document is stable and deterministic

    func testRoundTripPreservesDocument() throws {
        let (graph, ids) = try Graph.load(pricingDoc, catalog: catalog)
        let again = graph.document(using: ids)
        XCTAssertEqual(again, pricingDoc)
    }

    func testSaveIsDeterministic() throws {
        let (graph, ids) = try Graph.load(pricingDoc, catalog: catalog)
        XCTAssertEqual(graph.document(using: ids), graph.document(using: ids))
    }

    // MARK: A graph built in code serializes with readable, unique ids

    func testInCodeGraphGetsReadableGeneratedIDs() throws {
        var graph = Graph()
        _ = graph.addInput(try catalog.quantity(2, "m"), name: "width")
        _ = graph.addInput(try catalog.quantity(3, "m"), name: "width") // duplicate name

        let doc = graph.document()
        let generated = Set(doc.nodes.map(\.id))
        XCTAssertEqual(generated, ["width", "width_2"])
    }

    // MARK: Structural load errors are surfaced eagerly

    func testUnknownUnitIsRejected() {
        let doc = GraphDocument(
            nodes: [NodeDocument(id: "x", kind: "input", value: 1, unit: "furlong_per_fortnight")],
            edges: []
        )
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .unknownUnit(node: "x", symbol: "furlong_per_fortnight"))
        }
    }

    func testUnknownKindIsRejected() {
        let doc = GraphDocument(nodes: [NodeDocument(id: "x", kind: "modulo")], edges: [])
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .unknownKind(node: "x", kind: "modulo"))
        }
    }

    func testInputWithoutValueIsRejected() {
        let doc = GraphDocument(nodes: [NodeDocument(id: "x", kind: "input")], edges: [])
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .missingInputValue(node: "x"))
        }
    }

    func testDuplicateNodeIDIsRejected() {
        let doc = GraphDocument(
            nodes: [
                NodeDocument(id: "x", kind: "input", value: 1, unit: "m"),
                NodeDocument(id: "x", kind: "input", value: 2, unit: "m")
            ],
            edges: []
        )
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .duplicateNodeID("x"))
        }
    }

    func testEdgeToUnknownNodeIsRejected() {
        let doc = GraphDocument(
            nodes: [NodeDocument(id: "a", kind: "input", value: 1, unit: "m")],
            edges: [EdgeDocument(from: EndpointRef(node: "a"), to: EndpointRef(node: "ghost", port: "a"))]
        )
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .unknownNode("ghost"))
        }
    }

    func testEdgeToUnknownPortIsRejected() {
        let doc = GraphDocument(
            nodes: [
                NodeDocument(id: "a", kind: "input", value: 1, unit: "m"),
                NodeDocument(id: "m", kind: "multiply")
            ],
            edges: [EdgeDocument(from: EndpointRef(node: "a"), to: EndpointRef(node: "m", port: "z"))]
        )
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .unknownPort(node: "m", port: "z"))
        }
    }

    func testUnsupportedSchemaVersionIsRejected() {
        let doc = GraphDocument(schemaVersion: 999, nodes: [], edges: [])
        XCTAssertThrowsError(try Graph.load(doc, catalog: catalog)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedSchemaVersion(999))
        }
    }
}
