# GuyLine

**A typed dataflow canvas where physical units are part of the verification.**

GuyLine is a macOS app (SwiftUI, open source) that is a hybrid of a spreadsheet
and a flow chart. You connect formulae as a **node graph**: components have
dimensioned input/output ports, wires show data flow, and any
dimensionally-impossible connection is flagged. Units aren't decoration — they're
a *type system* for numbers. A m³ must have three length contributions; a
`$/m³ × m³` must reduce to `$`. If it doesn't, GuyLine paints it red.

The use case is **engineering, estimating, and AEC** — where unit mistakes
are silent and expensive. Price something per linear metre when the quantity is
an area, and a spreadsheet will happily give you a confident, wrong number.
GuyLine won't: the dimensional checker is a correctness *engine*, and the same
public API that the UI draws is the one an AI agent can drive; propose a graph,
read back the exact dimensional fault, repair it.  A tool that humans and AI can use to prove units are coherent and in sync. 

Conceptual cousins: Grasshopper, Dynamo, Mathcad.

## Why "GuyLine"?

A **guy-line** is the tension cable that holds a tower, mast, or tent dead
upright and true — the thing that keeps a structure from drifting out of plumb.

It's also a homophone for **guideline**: the rule that keeps you correct.

That double meaning is the whole product in one word. GuyLine is the cable that
keeps your numbers *true* — every wire under tension, every dimension held in
line.

## Architecture

The project is deliberately split so the engines never depend on the UI:

| Module           | What it is                                                            |
| ---------------- | --------------------------------------------------------------------- |
| `QuantityKernel` | Dimensional algebra - wraps the [Units](https://github.com/NeedleInAJayStack/Units) library; knows nothing of UI. |
| `GraphEngine`    | Headless dataflow engine - nodes, ports, wires, topological recompute, dimension propagation. Pure, cross-platform. |
| `GuyLineApp`     | The SwiftUI macOS front-end - a thin *consumer* of the engines' public API. |

Three goals: (1) strict engine/UI separation, (2) keep the engines
cross-platform-capable, (3) an interface for AI to drive the engines against the
dimensional oracle. The human UI and the AI consume the same public API and
document format. See [`docs/design/engine-interface.md`](docs/design/engine-interface.md).

## Running it

```sh
swift run GuyLineApp   # launches the macOS app with a demo concrete-pricing graph
swift test             # runs the engine + kernel test suites
```
