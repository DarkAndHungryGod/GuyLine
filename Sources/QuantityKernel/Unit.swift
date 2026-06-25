import Units

/// A unit of measure — simple (`m`, `kg`, `$`) or composite (`$/m^3`, `kg*m/s^2`).
///
/// A `Unit` carries a dimension (length, mass, money, …) independent of any
/// numeric value, which is what lets the graph layer check whether two ports are
/// compatible *before* any numbers are entered.
public struct Unit: Equatable, Sendable {
    let raw: Units.Unit

    init(_ raw: Units.Unit) {
        self.raw = raw
    }

    /// The dimensionless unit: a pure number that carries no physical dimension
    /// and adopts the other operand's units under multiplication (`5 × $ → $`).
    /// This is what lets a bare count — "5 piles" — scale a dimensioned value.
    public static var scalar: Unit { Unit(.none) }

    /// Whether this unit has no dimension (a bare count or a ratio that cancelled).
    public var isDimensionless: Bool { raw.dimension.isEmpty }

    /// The unit's symbol, e.g. `"m^3"` or `"$/m^3"`.
    public var symbol: String { raw.symbol }

    /// A human-readable description of the unit's dimension, e.g. `"Length^3"`
    /// or `"Money/Length^3"`.
    public var dimensionDescription: String { raw.dimensionDescription() }

    /// Whether two units describe the same physical dimension (e.g. `m` and `ft`,
    /// or `$/m^3` and `$/L`). This is the core port-compatibility check.
    public func isDimensionallyEquivalent(to other: Unit) -> Bool {
        raw.isDimensionallyEquivalent(to: other.raw)
    }

    /// The product of two units (`m` × `m` → `m^2`).
    public static func * (lhs: Unit, rhs: Unit) -> Unit {
        Unit(lhs.raw * rhs.raw)
    }

    /// The quotient of two units (`$` / `m^3` → `$/m^3`).
    public static func / (lhs: Unit, rhs: Unit) -> Unit {
        Unit(lhs.raw / rhs.raw)
    }

    /// The unit raised to an integer power (`m` to the 3rd → `m^3`).
    public func power(_ exponent: Int) -> Unit {
        Unit(raw.pow(exponent))
    }
}
