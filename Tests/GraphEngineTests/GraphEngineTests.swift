import XCTest
import QuantityKernel
@testable import GraphEngine

/// Tests for the headless dataflow engine. These build small graphs and check
/// that values propagate, dimensions combine, and the failure modes a UI needs
/// to paint red (missing inputs, cycles, dimensional mistakes) are surfaced as
/// recoverable per-node errors rather than thrown.
final class GraphEngineTests: XCTestCase {
    private let catalog = UnitCatalog.standard

    // MARK: A simple chain computes and propagates dimensions (m × m × m = m³)

    func testVolumeFromThreeLengthInputs() throws {
        var graph = Graph()
        let w = graph.addInput(try catalog.quantity(2, "m"), name: "width")
        let d = graph.addInput(try catalog.quantity(3, "m"), name: "depth")
        let h = graph.addInput(try catalog.quantity(4, "m"), name: "height")
        let area = graph.addNode(.multiply, name: "area")
        let volume = graph.addNode(.multiply, name: "volume")

        try graph.connect(OutputEndpoint(w), to: InputEndpoint(area, 0))
        try graph.connect(OutputEndpoint(d), to: InputEndpoint(area, 1))
        try graph.connect(OutputEndpoint(area), to: InputEndpoint(volume, 0))
        try graph.connect(OutputEndpoint(h), to: InputEndpoint(volume, 1))

        let result = graph.evaluate()

        XCTAssertTrue(result.isFullyResolved)
        let out = try XCTUnwrap(result.value(of: volume))
        XCTAssertEqual(out.value, 24, accuracy: 1e-9)
        let cubicMeter = try catalog.unit("m").power(3)
        XCTAssertTrue(out.isDimensionallyEquivalent(to: cubicMeter))
    }

    // MARK: The core value proposition — a correct price graph reduces to $

    func testConcretePriceGraphResolvesToDollars() throws {
        var graph = Graph()
        let cubicMeter = try catalog.unit("m").power(3)
        let dollar = try catalog.unit("$")

        let rate = graph.addInput(Quantity(value: 180, unit: dollar / cubicMeter), name: "rate")
        let pour = graph.addInput(Quantity(value: 24, unit: cubicMeter), name: "pour")
        let cost = graph.addNode(.multiply, name: "cost")

        try graph.connect(OutputEndpoint(rate), to: InputEndpoint(cost, 0))
        try graph.connect(OutputEndpoint(pour), to: InputEndpoint(cost, 1))

        let out = try XCTUnwrap(graph.evaluate().value(of: cost))
        XCTAssertEqual(out.value, 4320, accuracy: 1e-9)
        XCTAssertTrue(out.isDimensionallyEquivalent(to: dollar))
        XCTAssertEqual(out.unit.dimensionDescription, "Money")
    }

    // MARK: The silent mistake — per-LINEAR-metre rate against an AREA

    func testPerLinearMetreRateAgainstAreaDoesNotReadAsCurrency() throws {
        var graph = Graph()
        let meter = try catalog.unit("m")
        let dollar = try catalog.unit("$")

        let rate = graph.addInput(Quantity(value: 12, unit: dollar / meter), name: "edge rate")
        let area = graph.addInput(Quantity(value: 50, unit: meter.power(2)), name: "area")
        let total = graph.addNode(.multiply, name: "total")

        try graph.connect(OutputEndpoint(rate), to: InputEndpoint(total, 0))
        try graph.connect(OutputEndpoint(area), to: InputEndpoint(total, 1))

        let out = try XCTUnwrap(graph.evaluate().value(of: total))
        // The number is plausible (600) but the units betray the mistake.
        XCTAssertEqual(out.value, 600, accuracy: 1e-9)
        XCTAssertFalse(out.isDimensionallyEquivalent(to: dollar))
        XCTAssertTrue(out.isDimensionallyEquivalent(to: dollar * meter))
    }

    // MARK: Adding incompatible dimensions fails the node, not the program

    func testAddingLengthToMassReportsKernelError() throws {
        var graph = Graph()
        let length = graph.addInput(try catalog.quantity(1, "m"))
        let mass = graph.addInput(try catalog.quantity(1, "kg"))
        let sum = graph.addNode(.add)

        try graph.connect(OutputEndpoint(length), to: InputEndpoint(sum, 0))
        try graph.connect(OutputEndpoint(mass), to: InputEndpoint(sum, 1))

        let result = graph.evaluate()
        XCTAssertNil(result.value(of: sum))
        guard case .kernel(.incompatibleDimensions) = result.errors[sum] else {
            return XCTFail("Expected a kernel dimension error, got \(String(describing: result.errors[sum]))")
        }
    }

    // MARK: Compatible units auto-convert through an add node (5 mm + 1 m)

    func testMixedLengthUnitsAddThroughGraph() throws {
        var graph = Graph()
        let small = graph.addInput(try catalog.quantity(5, "mm"))
        let big = graph.addInput(try catalog.quantity(1, "m"))
        let sum = graph.addNode(.add)

        try graph.connect(OutputEndpoint(small), to: InputEndpoint(sum, 0))
        try graph.connect(OutputEndpoint(big), to: InputEndpoint(sum, 1))

        let out = try XCTUnwrap(graph.evaluate().value(of: sum))
        let inMeters = try out.converted(to: catalog.unit("m"))
        XCTAssertEqual(inMeters.value, 1.005, accuracy: 1e-9)
    }

    // MARK: An unwired input port is reported, and blocks dependents

    func testMissingInputBlocksDownstream() throws {
        var graph = Graph()
        let a = graph.addInput(try catalog.quantity(2, "m"))
        let mul = graph.addNode(.multiply)        // port 1 left unwired
        let twice = graph.addNode(.multiply)

        try graph.connect(OutputEndpoint(a), to: InputEndpoint(mul, 0))
        try graph.connect(OutputEndpoint(mul), to: InputEndpoint(twice, 0))
        try graph.connect(OutputEndpoint(a), to: InputEndpoint(twice, 1))

        let result = graph.evaluate()
        XCTAssertEqual(result.errors[mul], .missingInput(port: 1))
        XCTAssertEqual(result.errors[twice], .upstreamFailure)
        XCTAssertNil(result.value(of: twice))
    }

    // MARK: A dependency cycle is reported, not hung on

    func testCycleIsReported() throws {
        var graph = Graph()
        let a = graph.addNode(.add)
        let b = graph.addNode(.add)
        // a feeds b and b feeds a — a cycle with no source.
        try graph.connect(OutputEndpoint(a), to: InputEndpoint(b, 0))
        try graph.connect(OutputEndpoint(b), to: InputEndpoint(a, 0))

        let result = graph.evaluate()
        XCTAssertEqual(result.errors[a], .cycle)
        XCTAssertEqual(result.errors[b], .cycle)
    }

    // MARK: Connection validation rejects a second wire into one input

    func testInputAcceptsAtMostOneWire() throws {
        var graph = Graph()
        let a = graph.addInput(try catalog.quantity(1, "m"))
        let b = graph.addInput(try catalog.quantity(2, "m"))
        let sum = graph.addNode(.add)

        try graph.connect(OutputEndpoint(a), to: InputEndpoint(sum, 0))
        XCTAssertThrowsError(try graph.connect(OutputEndpoint(b), to: InputEndpoint(sum, 0))) { error in
            guard case ConnectionError.inputAlreadyConnected = error else {
                return XCTFail("Expected inputAlreadyConnected, got \(error)")
            }
        }
    }

    // MARK: Connection validation rejects a non-existent port

    func testConnectingUnknownPortThrows() throws {
        var graph = Graph()
        let a = graph.addInput(try catalog.quantity(1, "m"))
        let sum = graph.addNode(.add)

        XCTAssertThrowsError(try graph.connect(OutputEndpoint(a), to: InputEndpoint(sum, 5))) { error in
            guard case ConnectionError.unknownPort = error else {
                return XCTFail("Expected unknownPort, got \(error)")
            }
        }
    }
}
