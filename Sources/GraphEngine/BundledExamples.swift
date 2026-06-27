import Foundation

/// A ready-made example graph shipped inside the engine, for first-run demos and
/// for showing the unit machinery off without the user building a graph by hand.
///
/// The graph itself travels as a ``GraphDocument`` (decoded from a bundled JSON
/// resource); `title`/`summary` are presentation metadata the document format
/// deliberately doesn't carry.
public struct GraphExample: Identifiable, Sendable {
    /// Stable identifier, matching the resource's file stem (e.g. `concrete-takeoff`).
    public let id: String
    /// Human-readable name for menus and window titles.
    public let title: String
    /// One-line description of what the example computes.
    public let summary: String
    /// The example's graph, ready to load into a `Graph` or a view model.
    public let document: GraphDocument
}

/// The example graphs bundled with the engine, in display order.
///
/// Each entry pairs presentation metadata with a `Examples/<id>.json` resource
/// decoded from `Bundle.module`. Keeping the catalogue here (rather than in the
/// UI) means any front-end — or the AI interface — gets the same set for free.
public enum BundledExamples {
    public static let all: [GraphExample] = [
        example(
            id: "concrete-takeoff",
            title: "Concrete Takeoff",
            summary: "Slab dimensions → volume → cement mass → bags → cost."
        ),
        example(
            id: "pump-energy-sizing",
            title: "Pump & Energy Sizing",
            summary: "ρ·g·Q·H hydraulic power → shaft power → energy → running cost."
        ),
    ]

    /// Look an example up by id.
    public static func example(id: String) -> GraphExample? {
        all.first { $0.id == id }
    }

    /// Decode the document for `id` from the engine's resource bundle. Traps on
    /// failure: these are first-party resources verified by the test suite, so a
    /// miss means a packaging bug, not a runtime condition to handle.
    private static func example(id: String, title: String, summary: String) -> GraphExample {
        guard let url = Bundle.module.url(
            forResource: id, withExtension: "json", subdirectory: "Examples"
        ) else {
            preconditionFailure("Missing bundled example resource: Examples/\(id).json")
        }
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(GraphDocument.self, from: data)
            return GraphExample(id: id, title: title, summary: summary, document: document)
        } catch {
            preconditionFailure("Could not decode bundled example \(id): \(error)")
        }
    }
}
