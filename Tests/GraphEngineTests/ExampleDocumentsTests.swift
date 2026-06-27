import XCTest
import QuantityKernel
@testable import GraphEngine

/// Loads the worked example graphs bundled with the engine and checks they
/// evaluate cleanly. Doubles as a way to *see* the numbers: run with
/// `swift test --filter ExampleDocumentsTests` and read the printed output.
final class ExampleDocumentsTests: XCTestCase {
    private let catalog = UnitCatalog.standard

    /// Print every node's computed value in document order.
    private func dump(_ example: GraphExample, _ graph: Graph, _ ids: IdMap) {
        let result = graph.evaluate()
        print("\n=== \(example.title) ===")
        for node in example.document.nodes {
            guard let nodeID = ids.nodeID(for: node.id) else { continue }
            let label = (node.name ?? node.id).padding(toLength: 30, withPad: " ", startingAt: 0)
            if let value = result.value(of: nodeID) {
                print("  \(label) = \(value)")
            } else if let error = result.errors[nodeID] {
                print("  \(label) ! \(error)")
            }
        }
    }

    /// Every bundled example loads and evaluates without a single node error.
    func testAllBundledExamplesEvaluateCleanly() throws {
        XCTAssertFalse(BundledExamples.all.isEmpty)
        for example in BundledExamples.all {
            let (graph, ids) = try Graph.load(example.document, catalog: catalog)
            let result = graph.evaluate()
            dump(example, graph, ids)
            XCTAssertTrue(
                result.isFullyResolved,
                "\(example.id) had errors: \(result.errors)"
            )
        }
    }

    func testConcreteTakeoffReducesToMoney() throws {
        let example = try XCTUnwrap(BundledExamples.example(id: "concrete-takeoff"))
        let (graph, ids) = try Graph.load(example.document, catalog: catalog)
        let result = graph.evaluate()
        let cost = try XCTUnwrap(result.value(of: ids.nodeID(for: "cost")!))
        XCTAssertTrue(cost.isDimensionallyEquivalent(to: try catalog.unit("$")))
    }

    func testPumpSizingReducesToPowerAndMoney() throws {
        let example = try XCTUnwrap(BundledExamples.example(id: "pump-energy-sizing"))
        let (graph, ids) = try Graph.load(example.document, catalog: catalog)
        let result = graph.evaluate()

        // ρ·g·Q·H must cancel to the power dimension (W); the final cost to money.
        let power = try XCTUnwrap(result.value(of: ids.nodeID(for: "hydraulic")!))
        XCTAssertTrue(power.isDimensionallyEquivalent(to: try catalog.unit("W")))
        let cost = try XCTUnwrap(result.value(of: ids.nodeID(for: "cost")!))
        XCTAssertTrue(cost.isDimensionallyEquivalent(to: try catalog.unit("$")))
    }
}
