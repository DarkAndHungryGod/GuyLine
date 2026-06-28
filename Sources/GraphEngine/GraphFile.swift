import Foundation

/// The on-disk file format for a GuyLine graph: the canonical ``GraphDocument``
/// (the semantics — what the engine and the AI layer care about) wrapped together
/// with **presentation** state (how a particular front-end chose to lay the graph
/// out — positions, selection, zoom).
///
/// This is the "superset file" from `docs/design/document-based-app.md`: layout
/// lives *around* the engine document, never mixed into it. The contract:
///
/// - A correctness-only consumer (the engine, an AI agent, a future cross-language
///   binding) reads just the `document` key and ignores everything else. The
///   ``DocumentOnly`` view below is exactly that read.
/// - A front-end that does care about layout decodes the whole file with its own
///   `Presentation` type, which the engine treats as opaque (hence the generic).
///
/// Presentation is intentionally not modelled here: positions are an
/// AppKit/SwiftUI concept (`CGPoint`), and the engine stays free of UI types so it
/// can be ported elsewhere. The front-end supplies the concrete shape.
public struct GraphFile<Presentation: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    /// The version of *this envelope's* schema — distinct from
    /// ``GraphDocument/schemaVersion``, which versions the graph payload. Bumped
    /// only when the file's outer shape changes (a new top-level key, say), so the
    /// two halves can evolve independently.
    public var formatVersion: Int

    /// The canonical, presentation-free graph. This is the sole thing a
    /// correctness-only consumer needs.
    public var document: GraphDocument

    /// Front-end layout state. Optional so a hand-authored or AI-emitted file can
    /// omit it entirely; the reader then falls back to auto-layout.
    public var presentation: Presentation?

    /// The envelope version this build reads and writes.
    public static var currentFormatVersion: Int { 1 }

    public init(
        document: GraphDocument,
        presentation: Presentation? = nil,
        formatVersion: Int? = nil
    ) {
        self.formatVersion = formatVersion ?? Self.currentFormatVersion
        self.document = document
        self.presentation = presentation
    }
}

// MARK: - Reading

extension GraphFile {
    /// Decode a file from JSON `data`, rejecting envelope versions this build does
    /// not understand before attempting to interpret the rest.
    ///
    /// The version is probed first (see ``DocumentOnly``-style minimal decode) so a
    /// genuinely-too-new file fails with a clear ``GraphFileError`` rather than an
    /// opaque presentation-shape mismatch.
    public static func decoded(from data: Data) throws -> GraphFile {
        let version = try JSONDecoder().decode(VersionProbe.self, from: data).formatVersion
        guard version == currentFormatVersion else {
            throw GraphFileError.unsupportedFormatVersion(version)
        }
        return try JSONDecoder().decode(GraphFile.self, from: data)
    }

    /// Encode this file to pretty-printed, slash-preserving JSON, with object keys
    /// sorted so the on-disk bytes are stable across saves (clean diffs, no
    /// spurious changes when only an unrelated edit happened).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Just the `formatVersion`, decoded on its own so a version check doesn't
    /// require decoding the (possibly future-shaped) rest of the file.
    private struct VersionProbe: Decodable {
        let formatVersion: Int
    }
}

/// A correctness-only view of a GuyLine file: the canonical ``GraphDocument``,
/// with any presentation state ignored.
///
/// This is the read the engine and the AI layer use — they get the graph without
/// having to know, or agree on, how a particular UI lays it out. It decodes any
/// ``GraphFile`` regardless of the presentation shape stored alongside.
public struct GraphFileDocument: Decodable, Sendable {
    public let document: GraphDocument

    public init(from data: Data) throws {
        self = try JSONDecoder().decode(GraphFileDocument.self, from: data)
    }
}

/// Why a ``GraphFile`` could not be read.
public enum GraphFileError: Error, Equatable, Sendable {
    /// The file's `formatVersion` is newer (or otherwise unknown) than this build
    /// can read.
    case unsupportedFormatVersion(Int)
}
