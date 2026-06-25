# Engine Interface Design

Status: **design / on paper** (no implementation yet). This is the contract that
the macOS UI, the AI agent layer, and any future cross-language binding all build
on top of.

## Critical design goals

These are load-bearing. Every decision below serves them, and new work should be
checked against them:

1. **Separation between engines and UI.** `QuantityKernel` and `GraphEngine` know
   nothing about SwiftUI/AppKit. All Mac code lives in `GuyLineApp` and is a
   thin *consumer* of the engines' public API — never woven into them. Today this
   holds: the only non-engine import below the app target is `Foundation` (for
   `UUID`) in `GraphEngine`.
2. **Keep the engines as cross-platform-capable as possible**, even before we ship
   anything off-Mac. No Apple-only APIs in the engines; no `platforms` floor that
   would gate them; prove it with a Linux build in CI when ready. The macOS
   platform requirement belongs to the app, not the core.
3. **Work toward an interface for AI to drive the engines** for correct execution
   of unit-proofed graphs. The dimensional checker is a built-in *correctness
   oracle*: the AI proposes a graph, the engine reports exactly which connection
   is dimensionally wrong, the AI repairs. The serialized document + result
   formats below exist to make that loop tight and language-neutral.

The unifying rule: **the human UI and the AI consume the exact same public API and
document format.** The UI is the AI interface's first and most demanding client,
so building the UI on this contract keeps it honest.

## The graph document (`GraphDocument`)

The canonical, serializable, language-neutral representation of a graph. JSON,
versioned, `Codable`. Example — the flagship concrete-pricing graph:

```json
{
  "schemaVersion": 1,
  "nodes": [
    { "id": "area",  "kind": "input",    "name": "Floor area", "value": 50, "unit": "m^2" },
    { "id": "rate",  "kind": "input",    "name": "Unit rate",  "value": 30, "unit": "$/m^2" },
    { "id": "total", "kind": "multiply", "name": "Total cost" }
  ],
  "edges": [
    { "from": "area", "to": { "node": "total", "port": "a" } },
    { "from": "rate", "to": { "node": "total", "port": "b" } }
  ]
}
```

Design decisions:

- **Author-chosen string ids** (`"area"`, `"rate"`, `"total"`), not UUIDs. They are
  stable, meaningful, and make every error message legible. Internally the engine
  keeps `NodeID` (UUID) for identity stability; the document boundary maps
  string-id ↔ `NodeID`. The internal identity model does not change.
- **Ports referenced by name** (`"a"`, `"b"`, `"out"`), resolved to indices on
  load. More robust to AI authoring and to new node kinds than raw indices.
- `from` may be a bare id (defaults to the `"out"` port) or `{ "node", "port" }`
  for future multi-output nodes.
- **Units are symbol strings**, resolved through `UnitCatalog`. Unknown symbols
  become *load diagnostics*, never crashes.
- **No coordinates or UI state.** Layout lives in a separate optional presentation
  sidecar (below), so the engine stays layout-agnostic and the AI never deals with
  pixels.
- Forward-compatible: `schemaVersion` gates changes; unknown fields are ignored.

### Presentation sidecar (UI-only, optional)

Keyed by the same node ids; the engine package does not need to know it exists.

```json
{ "schemaVersion": 1,
  "positions": { "area": {"x":40,"y":80}, "rate": {"x":40,"y":200}, "total": {"x":300,"y":140} } }
```

## The result document

What `evaluate()` produces, serialized for an AI/cross-language consumer. Every
value carries its **dimension string** — the key self-check channel for unit
proofing.

```json
{
  "values": {
    "area":  { "value": 50,   "unit": "m^2",   "dimension": "Length^2" },
    "rate":  { "value": 30,   "unit": "$/m^2", "dimension": "Money/Length^2" },
    "total": { "value": 1500, "unit": "$",     "dimension": "Money" }
  },
  "errors": {},
  "fullyResolved": true
}
```

The oracle in action — wire the wrong rate into an `add` and the engine says
exactly why:

```json
"errors": {
  "total": { "code": "incompatibleDimensions", "message": "Cannot add $/m^2 to m^2" }
}
```

Error codes map 1:1 to the existing enums: `missingInput`, `upstreamFailure`,
`cycle`, `incompatibleDimensions`, `unknownUnit`.

## The node catalog schema

A machine-readable description of the node vocabulary, **generated from
`NodeKind`** so it can never drift from the implementation. Doubles as the AI's
reference documentation.

```json
{
  "kinds": [
    { "kind": "input", "inputs": [], "outputs": ["out"],
      "params": [ {"name":"value","type":"number"}, {"name":"unit","type":"unitSymbol"} ],
      "doc": "A literal source value with a unit." },
    { "kind": "multiply", "inputs": ["a","b"], "outputs": ["out"],
      "dimensionRule": "out = a × b (dimensions combine, never conflict)",
      "doc": "Product of two quantities." },
    { "kind": "add", "inputs": ["a","b"], "outputs": ["out"],
      "dimensionRule": "out = a + b (requires matching dimensions)",
      "doc": "Sum of two quantities; errors if dimensions disagree." }
  ]
}
```

## Public API surface (Swift)

What both the UI and the AI/CLI call. Most of the building API already exists on
`Graph` (`addNode`, `addInput`, `connect`, `updateNode`, `renameNode`,
`disconnect`, `removeNode`, `evaluate`). Additions needed for this contract — shape
only, not yet implemented:

| Addition | Purpose |
|---|---|
| `GraphDocument: Codable, Sendable` | the wire format above |
| `Graph.init(document:catalog:) throws` → `(Graph, IdMap)` | load; resolves unit symbols, validates structure, returns diagnostics |
| `Graph.document(idMap:) -> GraphDocument` | save |
| `Graph.addNode(id:kind:name:)` | explicit-id variant so loading preserves author ids (current one mints a UUID; keep it as convenience) |
| `GraphResult.document(idMap:) -> ResultDocument` | serialize values + errors with dimension strings |
| `NodeCatalog.schema()` | emit the kinds vocabulary JSON |

`evaluate()` is unchanged.

## The headless front door

A tiny **non-Mac executable** target (`guyline`) — and later an MCP server —
exposing exactly:

- `guyline eval <doc.json>` → result JSON
- `guyline catalog` → node-catalog schema JSON
- (later) builder/mutation commands

This is what the AI, a Python binding, and a Linux build all use. It imports zero
Mac code, which both delivers goal 3 and *proves* goals 1 and 2.

## Build order (each step independent and low-risk)

1. `Codable` model + `GraphDocument` round-trip (load/save, id mapping).
2. Result + catalog serialization (the AI feedback channel).
3. `guyline` headless CLI on top of (1) and (2).
4. Split the engines into their own package with no platform floor; add a Linux
   CI build to guard goals 1 and 2 permanently.
5. MCP server / agent tools over the CLI; migrate the UI to consume
   `GraphDocument` + presentation sidecar instead of reaching into the engine.
