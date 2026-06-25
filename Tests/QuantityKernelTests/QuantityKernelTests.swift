import XCTest
@testable import QuantityKernel

/// Tests for the QuantityKernel wrapper — the same estimating scenarios proven
/// in the original spike, now expressed entirely through the kernel's public API
/// (no direct dependency on the underlying Units package). This is also the proof
/// that the wrapper boundary is complete: these tests never `import Units`.
final class QuantityKernelTests: XCTestCase {
    private let catalog = UnitCatalog.standard

    // MARK: Compound dimensions are derived by arithmetic (m × m × m = m³)

    func testVolumeIsDerivedFromThreeLengths() throws {
        let meter = try catalog.unit("m")
        let width = Quantity(value: 2, unit: meter)
        let depth = Quantity(value: 3, unit: meter)
        let height = Quantity(value: 4, unit: meter)

        let volume = width * depth * height

        XCTAssertEqual(volume.value, 24, accuracy: 1e-9)
        XCTAssertTrue(volume.isDimensionallyEquivalent(to: meter.power(3)))
        XCTAssertFalse(volume.isDimensionallyEquivalent(to: meter.power(2)))
    }

    // MARK: Pricing resolves to pure currency ($/m³ × m³ = $)

    func testConcreteCostResolvesToDollars() throws {
        let cubicMeter = try catalog.unit("m").power(3)
        let dollar = try catalog.unit("$")

        let rate = Quantity(value: 180, unit: dollar / cubicMeter) // $180 per m³
        let pour = Quantity(value: 24, unit: cubicMeter) // 24 m³

        let cost = rate * pour

        XCTAssertEqual(cost.value, 4320, accuracy: 1e-9)
        XCTAssertTrue(cost.isDimensionallyEquivalent(to: dollar))
        XCTAssertEqual(cost.unit.dimensionDescription, "Money")
    }

    // MARK: The silent error — per-LINEAR-metre rate against an AREA

    func testPerLinearMetreRateAgainstAreaIsFlaggable() throws {
        let meter = try catalog.unit("m")
        let dollar = try catalog.unit("$")

        let edgeRate = Quantity(value: 12, unit: dollar / meter) // $12 per linear m
        let area = Quantity(value: 50, unit: meter.power(2)) // 50 m²

        let result = edgeRate * area

        // The number looks fine; the units do not read as pure currency.
        XCTAssertEqual(result.value, 600, accuracy: 1e-9)
        XCTAssertFalse(result.isDimensionallyEquivalent(to: dollar),
                       "A per-linear-metre rate applied to an area must not read as pure currency")
        XCTAssertTrue(result.isDimensionallyEquivalent(to: dollar * meter))
    }

    // MARK: Compatible units auto-convert on addition (mm + m)

    func testMixedLengthUnitsAddCorrectly() throws {
        let meter = try catalog.unit("m")
        let millimeter = try catalog.unit("mm")

        let total = try Quantity(value: 5, unit: millimeter) + Quantity(value: 1, unit: meter)
        let inMeters = try total.converted(to: meter)

        XCTAssertEqual(inMeters.value, 1.005, accuracy: 1e-9)
    }

    // MARK: Incompatible addition throws a catchable KernelError

    func testAddingIncompatibleDimensionsThrows() throws {
        let meter = try catalog.unit("m")
        let kilogram = try catalog.unit("kg")

        XCTAssertThrowsError(
            try Quantity(value: 1, unit: meter) + Quantity(value: 1, unit: kilogram)
        ) { error in
            guard case KernelError.incompatibleDimensions = error else {
                return XCTFail("Expected KernelError.incompatibleDimensions, got \(error)")
            }
        }
    }

    // MARK: Conversion across compound units (m³ → litres)

    func testCubicMetreConvertsToLitres() throws {
        let litre = try catalog.unit("L")
        let volume = try Quantity(value: 1, unit: catalog.unit("m").power(3))

        let inLitres = try volume.converted(to: litre)

        XCTAssertEqual(inLitres.value, 1000, accuracy: 1e-6)
    }

    // MARK: Unknown symbols surface as a recoverable error

    func testUnknownUnitThrows() {
        XCTAssertThrowsError(try catalog.unit("smoot")) { error in
            guard case KernelError.unknownUnit(let symbol) = error else {
                return XCTFail("Expected KernelError.unknownUnit, got \(error)")
            }
            XCTAssertEqual(symbol, "smoot")
        }
    }

    // MARK: A dimensionless number carries the other operand's units (5 × $/pile)

    func testScalarCountScalesDollarsAndKeepsUnits() throws {
        let cubicMeter = try catalog.unit("m").power(3)
        let dollar = try catalog.unit("$")

        let rate = Quantity(value: 200, unit: dollar / cubicMeter) // $200/m³
        let pourPerPile = Quantity(value: 24, unit: cubicMeter)    // 24 m³ per pile
        let piles = Quantity(scalar: 5)                            // 5 piles, no unit

        let total = rate * pourPerPile * piles

        XCTAssertEqual(total.value, 24000, accuracy: 1e-9)
        XCTAssertTrue(total.isDimensionallyEquivalent(to: dollar))
        XCTAssertEqual(total.unit.dimensionDescription, "Money")
        XCTAssertFalse(total.isDimensionless)
        XCTAssertTrue(piles.isDimensionless)
    }

    // MARK: A blank unit symbol resolves to the dimensionless unit

    func testBlankSymbolIsDimensionless() throws {
        let count = try catalog.quantity(5, "")
        XCTAssertTrue(count.isDimensionless)
        XCTAssertEqual(count.value, 5, accuracy: 1e-9)

        // Two dimensionless numbers add; a number plus a length does not.
        let sum = try count + Quantity(scalar: 3)
        XCTAssertEqual(sum.value, 8, accuracy: 1e-9)
        XCTAssertThrowsError(try count + catalog.quantity(1, "m"))
    }

    // MARK: Convenience constructor

    func testCatalogQuantityConvenience() throws {
        let price = try catalog.quantity(99.5, "$")
        XCTAssertEqual(price.value, 99.5, accuracy: 1e-9)
        XCTAssertEqual(price.unit.dimensionDescription, "Money")
    }
}
