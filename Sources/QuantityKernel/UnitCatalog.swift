import Units

// The `Money` dimension lives here, behind the kernel boundary. Defining it as a
// dedicated dimension (rather than reusing a physical base quantity) means a price
// can never silently cancel against an unrelated unit. Relies on the extensible
// `Quantity` from our Units fork.
extension Units.Quantity {
    static let money = Units.Quantity(rawValue: "Money")
}

/// Vends `Unit` values by symbol from a fixed registry.
///
/// The catalog is the single place that knows about the underlying `Units`
/// package and the currency units we add on top of it. Everything else in the
/// app goes through this type, so the dependency never leaks.
public final class UnitCatalog: Sendable {
    /// The standard catalog: every unit the `Units` package defines, plus `$`.
    public static let standard = UnitCatalog()

    let registry: Registry

    /// Builds a catalog. Currently adds a single `$` currency unit; this is the
    /// seam where additional currencies or domain units will be registered.
    public init() {
        let builder = RegistryBuilder()
        // swiftlint:disable:next force_try - the symbol/dimension are constant and valid.
        try! builder.addUnit(
            name: "dollar",
            symbol: "$",
            dimension: [.money: 1],
            coefficient: 1
        )
        registry = builder.registry()
    }

    /// Look up a unit by its symbol, e.g. `"m"`, `"mm"`, `"kg"`, `"$"`, or a
    /// composite like `"$/m^3"`.
    /// - Throws: ``KernelError/unknownUnit(symbol:)`` if the symbol is unknown.
    public func unit(_ symbol: String) throws -> Unit {
        // A blank symbol means "no unit" — a dimensionless number.
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .scalar }
        do {
            return Unit(try Units.Unit(fromSymbol: trimmed, registry: registry))
        } catch {
            throw KernelError.unknownUnit(symbol: symbol)
        }
    }

    /// Convenience: build a ``Quantity`` directly from a value and unit symbol.
    public func quantity(_ value: Double, _ symbol: String) throws -> Quantity {
        Quantity(value: value, unit: try unit(symbol))
    }
}
