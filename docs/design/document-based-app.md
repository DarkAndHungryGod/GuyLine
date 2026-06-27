# Document-Based App

Status: **design / on paper** — this is the next major piece of app work.

## Current state

`GuyLineApp` is **not** document-based. [`GuyLineApp.swift`](../../Sources/GuyLineApp/GuyLineApp.swift)
uses a single `WindowGroup` with one app-level `@StateObject vm =
GraphViewModel.demo()`. Consequences:

- ⌘N can open a second window, but every window shares the *same* view model and
  therefore the same graph — it is effectively single-document, single-state.
- No open / save / recent / autosave; the Examples menu loads into the *current*
  window, replacing whatever was there.
- The graph only lives in memory; there is no on-disk file the user owns.

The serialization groundwork is already done: `GraphDocument` is `Codable` with
stable string ids and a load → edit → save round-trip (`Graph.load` /
`Graph.document`). That is the file payload; this work is the app shell around it.

## Goal

Move to a `DocumentGroup` so each graph is a real document in its own window,
with the standard macOS behaviours falling out for free:

- Multiple independent documents/windows (the real multi-window answer).
- Open, Save, Save As, Open Recent, autosave + versions.
- **Undo/redo** via the document's `UndoManager`. Structural edits already funnel
  through mutating methods on `GraphViewModel`, so registering undo there is
  tractable.
- "New from Example" — open a bundled example as a new *untitled* document
  instead of overwriting the current graph.

## Design decisions to make

### 1. `FileDocument` vs. `ReferenceFileDocument`

`GraphViewModel` is a reference type (`ObservableObject`), and graphs can carry
nontrivial state. `ReferenceFileDocument` (class-based, with explicit snapshotting
for undo/autosave) is the more natural fit; `FileDocument` (value type) is simpler
but would mean reworking the model into a struct. Decide early — it shapes the
view-model refactor.

### 2. The on-disk format: semantics vs. presentation

This is the load-bearing decision, and it collides with two project rules
(see [engine-interface.md](engine-interface.md)): **engine/UI separation** and
**the human UI and the AI consume the same document format**.

`GraphDocument` deliberately holds **no layout** — no node positions, no
selection, no zoom. A document-based app must persist that presentation state, or
every reopen re-auto-lays-out the graph. Options:

1. **Superset file:** the file is `{ "document": {…GraphDocument…},
   "presentation": { "positions": {…}, … } }`. The engine/AI read only the
   `document` half and ignore presentation; the app reads both. Keeps
   `GraphDocument` pure and keeps the AI contract unchanged.
2. **Optional `presentation` key on the document** that the engine ignores.
   Flatter, but blurs the boundary the engine doc is meant to hold.

Leaning toward **(1)**: presentation is layered *around* the canonical engine
document, not mixed into it, which preserves separation and lets the AI keep
emitting plain `GraphDocument`s.

### 3. File type / UTI

Register a document type and extension (candidate: `.guyline`, exported UTI
conforming to `public.json`). Decide whether the engine `GraphDocument` JSON and
the app's document file are the same extension or distinct.

### 4. View-model migration

Move state off the App-level `@StateObject` into a per-document model created from
the opened file. First-run / `New` becomes an untitled empty (or example-seeded)
document rather than the hardcoded `GraphViewModel.demo()`. Auto-layout
(`GraphViewModel.autoLayout`) is the fallback when a file has no saved positions.

## Sequencing

Reasonable order once started: (1) pick `ReferenceFileDocument`, (2) define the
superset file format + UTI, (3) refactor `GraphViewModel` to per-document, (4)
swap `WindowGroup` → `DocumentGroup`, (5) wire undo, (6) "New from Example."
