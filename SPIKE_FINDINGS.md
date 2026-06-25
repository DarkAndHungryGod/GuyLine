# Units kernel — evaluation spike findings

**Date:** 2026-06-21
**Library evaluated:** [NeedleInAJayStack/Units](https://github.com/NeedleInAJayStack/Units) v1.1.0 (MIT)
**Toolchain:** Swift 6.2.4 / Xcode 26.3
**Result:** ✅ Adopt as the calculation kernel — all 6 scenarios pass (`swift test`).

## What was proven

| # | Scenario | Outcome |
|---|----------|---------|
| 1 | `m × m × m` derives `m³` (and is *not* an area) | ✅ compound dimensions derived by arithmetic |
| 2 | `$/m³ × m³` resolves to pure `$` | ✅ rates cancel cleanly to currency |
| 3 | `$/m` (per linear metre) × `m²` (area) → `$·m`, **not** `$` | ✅ the silent spreadsheet error is detectable |
| 4 | `5 mm + 1 m` → `1.005 m` | ✅ compatible units auto-convert on add |
| 5 | `1 m + 1 kg` | ✅ throws `UnitError.incompatibleUnits` (catchable, no crash) |
| 6 | `1 m³` → `1000 L` | ✅ conversion across compound units |

Scenario 3 is the core value proposition: the number (600) looks plausible, but
the *units* are wrong, and the kernel can flag it.

## Key API facts (for building on top)

- `+` / `-` **throw** on dimension mismatch and auto-convert compatible units.
  → The app surfaces a recoverable red error, never a crash.
- `*` / `/` never throw; they combine dimensions.
- Useful surface: `Measurement.isDimensionallyEquivalent(to:)` (port-compatibility
  check for the node graph), `.convert(to:)`, `.pow(_:)`, `.unit`, `.value`.
- Custom units via `RegistryBuilder().addUnit(name:symbol:dimension:coefficient:constant:)`,
  then `Unit(fromSymbol:registry:)`.

## ⚠️ The one real limitation: currency is not a first-class dimension

`Units.Quantity` (the base-dimension list) is a **closed enum** —
`Amount, Current, Length, Mass, Temperature, Time, LuminousIntensity, Angle, Data` —
with an author `// TODO: Consider changing away from enum for extensibility`.
There is no `Money`.

In the spike, `$` is registered against the unused `LuminousIntensity` dimension.
It works, but it's a **hack**: `$ × candela` would silently "cancel," and any real
photometric unit would collide.

**Options for the real app (decide before building the kernel wrapper):**
1. **Fork Units** and add a `Money` case to `Quantity` (small, surgical change;
   we own the diff). *Recommended* if currency is central — and for an
   estimating tool, it is.
2. Keep the unused-dimension hack and forbid photometric units in the UI. Cheap,
   but leaky.
3. Handle money *outside* the dimensional engine (treat `$` as a scalar tag).
   Loses the `$/m³ × m³ = $` checking that makes the feature compelling.

Recommendation: **(1)**. Upstreaming a `Money`/extensible-dimension PR may even
be welcomed given the existing TODO.

## Architectural guardrail

Wrap the library behind a thin `protocol QuantityKernel` in our own module so the
rest of the app (graph engine, UI) never imports `Units` directly. That keeps the
fork/no-fork decision reversible and isolates the Foundation `Measurement`/`Unit`
name-collision workaround (we alias them in tests).

## How to run

```sh
swift test
```
