# Discrete Quantities & Rounding

Status: **design / on paper** (no implementation yet).

## The problem

The engine computes in continuous reals, but many real-world quantities are
**discrete** — they only exist in whole units or fixed increments:

- The concrete takeoff example divides cement mass by mass-per-bag and gets
  **201.6 bags**. You cannot buy 0.2 of a bag — procurement needs **202**.
- Rebar, timber, and pipe are sold in fixed stock lengths (e.g. 6 m); a 14 m run
  needs **3 × 6 m lengths**, not 2.33.
- Sheet goods (plasterboard, ply) come in whole sheets; tiles in whole boxes.

Today the graph silently propagates the fractional value into downstream cost,
understating it. We need a way to express "round this quantity to how it is
actually purchased/installed."

## Proposed feature: a rounding node

Add a **rounding operation** to `NodeKind`. Behaviour:

- **Modes:** `ceil` (round up — the common procurement case), `floor`, and
  `nearest`.
- **Increment (optional):** round to a multiple of a given step, not just to 1.
  6 m stock lengths → round up to the next multiple of 6 m. Default increment is
  1 (whole units).
- **Dimension rule:** rounding **preserves the operand's unit and dimension**
  (rounding 201.6 bags → 202 bags; rounding 14 m to a 6 m increment → 18 m). When
  an increment is supplied it must be **dimensionally compatible** with the
  operand — rounding metres to a multiple of kilograms is the kind of mistake the
  engine should reject, exactly like `add`.

### Engine impact: the first *unary* node

Every current `NodeKind` is either an `input` (no inputs) or a binary op
(`a`, `b`). A rounding node is **unary** (one value in, one out), which the port
model already supports but no kind yet uses. Two shape options:

1. **Mode as node configuration, increment as an optional second input port.**
   `kind: "round"` carries `mode` (and the default increment); a second port `by`
   can be wired to feed the increment as a *graph value*, so the step can itself
   be computed and unit-checked. Most flexible; fits the dataflow model.
2. **Separate kinds** (`ceil`, `floor`, `round`) with the increment as a literal
   parameter only. Simpler, but less composable and can't unit-check the step.

Leaning toward **(1)**: one `round` kind with a `mode` parameter and an optional
`by` input, because it keeps the increment a first-class dimensioned value and
avoids a kind explosion.

### Serialization (`GraphDocument`)

A rounding node needs to carry its `mode` (and, for the literal-increment form,
the step). This is the first node kind with a *parameter* beyond `value`/`unit`,
so the document schema gains an optional parameter slot — bump `schemaVersion`
and keep older docs readable. The AI interface treats `round` like any other
kind: it can insert one to fix an "answer is fractional but must be whole" case.

## Open questions

- One configurable `round` node vs. discrete `ceil`/`floor`/`round` kinds.
- Increment as a wired input port, a literal parameter, or both.
- How the UI surfaces mode/increment (inspector control on the node).
- Do we also want a "round for display only" vs. "round the value that flows
  downstream"? The procurement cases above need the **value** rounded so cost is
  correct; a display-only rounding is a separate, lighter concern.
