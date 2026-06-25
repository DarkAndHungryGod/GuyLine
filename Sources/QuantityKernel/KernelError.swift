/// Errors surfaced by the quantity kernel.
///
/// These are deliberately recoverable: the graph/UI layer turns them into
/// red "this connection doesn't make sense" feedback rather than crashing.
public enum KernelError: Error, Equatable, Sendable {
    /// A unit symbol was requested that the catalog does not know.
    case unknownUnit(symbol: String)

    /// An operation required matching dimensions and the operands disagreed
    /// (e.g. adding a length to a mass, or converting `m²` to `m³`).
    case incompatibleDimensions(message: String)
}
