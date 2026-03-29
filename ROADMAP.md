# Descripex Roadmap

**Vision:** Make Descripex-annotated libraries fully discoverable and consumable by AI agents through structured metadata and standard protocols.

**Current version:** v0.6.0 (unreleased)
**Completed work details:** See [CHANGELOG.md](CHANGELOG.md).

---

## Backlog

| # | Task | Score | Status |
|---|------|-------|--------|
| 20 | `mix descripex.manifest` static JSON export | [D:2/B:5/U:6 → Eff:2.75] 🎯 | ✅ |
| 15 | Schema validation helper using JSONSpec schemas | [D:5/B:5/U:5 → Eff:1.0] 📋 | 🔶 Deferred |

### Task 15: Schema Validation Helper (Deferred)

**Deferred 2026-03-29** — Impedance mismatch: JSON Schema validates JSON, but Elixir callers pass Elixir terms (atoms, tuples, keyword lists). Real consumers of these schemas are MCP tools and external agents at the transport layer, where validation naturally happens. Descripex's job is to *describe*, not *enforce*. Will revisit if someone asks for it.

### Rejected Tasks

Tasks considered and removed — documented so future instances don't re-propose them.

**~~Task 17: Generate llms.txt from Manifest~~** — Rejected. ex_doc v0.40+ already generates `llms.txt` from `@doc` text, and `api()` generates rich `@doc` text. Every Descripex-annotated library already gets llms.txt via `mix docs`. App-specific llms.txt (like Strip0x's HTTP API docs) correctly lives in the app layer, not the library.

**~~Task 18: Generate OpenAPI 3.1 from Manifest~~** — Rejected. OpenAPI describes HTTP APIs (methods, paths, request/response bodies). Descripex describes Elixir function contracts — it has no concept of HTTP routing, methods, or status codes. The mapping requires app-specific context that only the consuming app knows. Strip0x.OpenAPI works because it adds routing context. This belongs in the app layer.

---

## v0.6.0: JSONSpec Integration + MCP Tools (unreleased) ✅

| # | Task | Score | Status |
|---|------|-------|--------|
| 14 | JSONSpec integration for machine-readable type schemas | [D:5/B:8/U:8 → Eff:1.6] 🚀 | ✅ |
| 16 | `schema:` support on `returns:` declaration | [D:2/B:6/U:7 → Eff:3.25] 🎯 | ✅ |
| 19 | MCP tool schema generation from manifest | [D:3/B:9/U:9 → Eff:3.0] 🎯 | ✅ |
| 20 | `mix descripex.manifest` static JSON export | [D:2/B:5/U:6 → Eff:2.75] 🎯 | ✅ |

> 4 tasks complete. See [CHANGELOG.md](CHANGELOG.md#060---unreleased) for details.
> Added: `schema:` on params/opts/returns compiles to JSON Schema. `Descripex.MCP.tools/1` converts annotated modules into MCP tool definitions. `mix descripex.manifest` exports JSON manifests to disk.

## v0.5.3: JSON-Serializable Manifest Errors ✅

| # | Task | Score | Status |
|---|------|-------|--------|
| 13 | Normalize hints.errors for JSON serialization | 🐛 Bug fix | ✅ |

> 1 task complete. See [CHANGELOG.md](CHANGELOG.md#053---2026-03-26) for details.
> Fixed: `Manifest.build/1` normalizes atom/tuple errors to JSON-safe maps.

## v0.5.2: Multi-Arity Hints Root Cause Fix ✅

| # | Task | Score | Status |
|---|------|-------|--------|
| 12 | Propagate @doc hints: to all arities in BEAM docs chunk | 🐛 Bug fix | ✅ |

> 1 task complete. See [CHANGELOG.md](CHANGELOG.md#052---2026-03-15) for details.
> Fixed: `__before_compile__` now injects hints into the compiler's internal doc table for every arity.

## v0.5.1: Multi-Arity Hints Fix ✅

| # | Task | Score | Status |
|---|------|-------|--------|
| 11 | Fix Manifest multi-arity hints propagation | 🐛 Bug fix | ✅ |

> 1 task complete. See [CHANGELOG.md](CHANGELOG.md#051---2026-03-15) for details.
> Fixed: `Manifest.build/1` now uses `__api__/0` as authoritative hints source for all arities.

## v0.5.0: Multi-Arity Support ✅

| # | Task | Score | Status |
|---|------|-------|--------|
| 10 | Multi-arity function support | [D:4/B:7/U:7 → Eff:1.75] 🚀 | ✅ |

> 1 task complete. See [CHANGELOG.md](CHANGELOG.md#050---2026-03-12) for details.
> Fixed: param validation now works across all arities, handling both true multi-arity and default-argument functions.

## v0.4.1: BEAM Docs Coexistence ✅

| # | Task | D/B | Priority | Status |
|---|------|-----|----------|--------|
| 8 | Document BEAM docs tuple slot coexistence | D:1/B:6 → 6.0 🎯 | ✅ |
| 9 | Add SKILLS.md consumer guide | D:2/B:7 → 3.5 🎯 | ✅ |

> 2 tasks complete. See [CHANGELOG.md](CHANGELOG.md#041---2026-02-25) for details.
> Documented: manual `@doc` + `api()` coexistence, consumer discovery workflow.

## v0.4.0: Agent-Friendly Docs ✅

| # | Task | D/B | Priority | Status |
|---|------|-----|----------|--------|
| 1 | Add `## Errors` section to doc text | D:2/B:8 → 4.0 🎯 | ✅ |
| 2 | Extend `errors:` to accept keyword descriptions | D:2/B:5 → 2.5 🎯 | ✅ |
| 3 | Embed machine-readable contract block | D:4/B:9 → 2.25 🎯 | ✅ |
| 4 | Add `returns_example` option | D:3/B:5 → 1.67 🚀 | ✅ |
| 5 | Auto-generate `@moduledoc` function table | D:5/B:8 → 1.6 🚀 | ✅ |
| 6 | Add `composes_with` option | D:4/B:4 → 1.0 📋 | ✅ |
| 7 | Dogfood: self-describing library | D:4/B:7 → 1.75 🚀 | ✅ |

> 7 tasks complete. See [CHANGELOG.md](CHANGELOG.md#040---2026-02-25) for details.
> Built: errors, contract blocks, returns_example, moduledoc tables, composes_with, dogfooding.
