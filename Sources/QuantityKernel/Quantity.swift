import Units

/// A numeric value paired with a unit — the thing that flows along the wires of
/// the graph.
///
/// Multiplication and division always succeed and combine dimensions
/// (`$/m^3` × `m^3` → `$`). Addition and subtraction require matching dimensions
/// and throw ``KernelError/incompatibleDimensions(message:)`` otherwise — that
/// thrown error is the signal the UI turns into a visible mistake.
public struct Quantity: Equatable, Sendable {
    var raw: Units.Measurement

    init(_ raw: Units.Measurement) {
        self.raw = raw
    }

    /// Build a quantity from a value and a ``Unit``.
    public init(value: Double, unit: Unit) {
        raw = Units.Measurement(value: value, unit: unit.raw)
    }

    /// Build a dimensionless quantity — a bare number (e.g. a count of items)
    /// that carries no unit and scales whatever it multiplies.
    public init(scalar value: Double) {
        self.init(value: value, unit: .scalar)
    }

    /// Whether this quantity has no dimension (a pure number).
    public var isDimensionless: Bool { unit.isDimensionless }

    /// The scalar value in terms of ``unit``.
    public var value: Double { raw.value }

    /// The unit this quantity is expressed in.
    public var unit: Unit { Unit(raw.unit) }

    /// Whether this quantity shares a dimension with another (regardless of the
    /// specific unit or value).
    public func isDimensionallyEquivalent(to other: Quantity) -> Bool {
        raw.isDimensionallyEquivalent(to: other.raw)
    }

    /// Whether this quantity's dimension matches a bare ``Unit`` — useful for
    /// checking a value against an expected output port.
    public func isDimensionallyEquivalent(to expected: Unit) -> Bool {
        raw.unit.isDimensionallyEquivalent(to: expected.raw)
    }

    /// Re-express this quantity in a different, dimensionally-compatible unit.
    /// - Throws: ``KernelError/incompatibleDimensions(message:)`` if `target`
    ///   has a different dimension.
    public func converted(to target: Unit) throws -> Quantity {
        do {
            return Quantity(try raw.convert(to: target.raw))
        } catch {
            throw KernelError.incompatibleDimensions(
                message: "Cannot convert \(unit.symbol) to \(target.symbol)"
            )
        }
    }

    /// This quantity with its value rounded **up** to the next whole number,
    /// keeping the same unit (`201.6 bags → 202 bags`).
    ///
    /// This is the "discrete quantity" rule: things sold or installed only in
    /// whole units (bags of cement, sheets of ply) can't take a fractional value,
    /// and procurement always rounds *up* — 201.6 bags still needs 202 bought.
    /// An already-whole value is returned unchanged.
    public func roundedUpToWhole() -> Quantity {
        Quantity(value: value.rounded(.up), unit: unit)
    }

    // MARK: - Arithmetic

    /// Product of two quantities; dimensions combine.
    public static func * (lhs: Quantity, rhs: Quantity) -> Quantity {
        Quantity(lhs.raw * rhs.raw)
    }

    /// Quotient of two quantities; dimensions combine.
    public static func / (lhs: Quantity, rhs: Quantity) -> Quantity {
        Quantity(lhs.raw / rhs.raw)
    }

    /// Sum of two quantities. The right operand is converted into the left's
    /// unit first.
    /// - Throws: ``KernelError/incompatibleDimensions(message:)`` if the
    ///   dimensions differ.
    public static func + (lhs: Quantity, rhs: Quantity) throws -> Quantity {
        do {
            return Quantity(try lhs.raw + rhs.raw)
        } catch {
            throw KernelError.incompatibleDimensions(
                message: "Cannot add \(rhs.unit.symbol) to \(lhs.unit.symbol)"
            )
        }
    }

    /// Difference of two quantities. The right operand is converted into the
    /// left's unit first.
    /// - Throws: ``KernelError/incompatibleDimensions(message:)`` if the
    ///   dimensions differ.
    public static func - (lhs: Quantity, rhs: Quantity) throws -> Quantity {
        do {
            return Quantity(try lhs.raw - rhs.raw)
        } catch {
            throw KernelError.incompatibleDimensions(
                message: "Cannot subtract \(rhs.unit.symbol) from \(lhs.unit.symbol)"
            )
        }
    }
}

extension Quantity: CustomStringConvertible {
    public var description: String { raw.description }
}
