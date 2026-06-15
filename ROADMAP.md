# Descripex Roadmap

**Vision:** Make Descripex-annotated libraries fully discoverable and consumable by AI agents through structured metadata and standard protocols.

**Current version:** v0.9.1 (published 2026-06-12)
**Completed work details:** See [CHANGELOG.md](CHANGELOG.md).

> **Source of truth:** `roadmap/tasks.toml`, managed by `rmap`. This file is rendered — edit `tasks.toml` (or use `rmap` commands), then run `rmap render`. Task tables inside the `<!-- TASKS -->` marker pairs are overwritten; prose outside them is preserved.

<!-- FOCUS:BEGIN -->
**Focus phase:** 8 — Backlog (4 of 8 done · 0 in progress)

**Last shipped:** Task 24 — Reconcile __api__/0 spec-enrichment with the BEAM doc-chunk hints (or document the asymmetry) on 2026-06-15

**Up next:** Task 27 — Fix pre-existing Dialyzer pattern_match warning in lib/descripex.ex (macro-generated 'false can never match true') [D:4/B:3/U:3 → Eff:0.75] ⚠️
<!-- FOCUS:END -->

---

## Backlog

<!-- TASKS:BEGIN phase=8 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 15 | 🔶 | 🎁 **backlog** · Schema validation helper using JSONSpec schemas [D:5/B:5/U:5 → Eff:1.0?] 📋 ⛔ Deferred 2026-03-29: impedance mismatch — JSON Schema validates JSON, but Elixir callers pass Elixir terms (atoms, tuples, keyword lists). |
| Task 17 | ⛔ | 🎁 **backlog** · Generate llms.txt from Manifest [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 18 | ⛔ | 🎁 **backlog** · Generate OpenAPI 3.1 from Manifest [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 21 | ✅ | 🎁 **jsonspec-mcp** · 🐛 Expose declared param order in __api__ so MCP consumers dispatch positionally [D:2/B:8/U:8 → Eff:4.0] 🎯 |
| Task 22 | ✅ | 🎁 **jsonspec-mcp** · 🐛 Emit typed JSON Schema for kind:value params — typeless properties make MCP clients mis-serialize [D:3/B:5/U:4 → Eff:1.5] 🚀 |
| Task 23 | ✅ | 🎁 **jsonspec-mcp** · 🐛 opts: section parity — emit typed JSON Schema for schema-less opts params too [D:2/B:3/U:3 → Eff:1.5] 🚀 |
| Task 24 | ✅ | 🎁 **jsonspec-mcp** · Reconcile __api__/0 spec-enrichment with the BEAM doc-chunk hints (or document the asymmetry) [D:4/B:5/U:6 → Eff:1.38] 📋 |
| Task 27 | ⬜ | 🎁 **backlog** · Fix pre-existing Dialyzer pattern_match warning in lib/descripex.ex (macro-generated 'false can never match true') [D:4/B:3/U:3 → Eff:0.75] ⚠️ |
<!-- TASKS:END -->

**Task 15 — Schema Validation Helper (deferred 2026-03-29):** Impedance mismatch — JSON Schema validates JSON, but Elixir callers pass Elixir terms (atoms, tuples, keyword lists). Real consumers of these schemas are MCP tools and external agents at the transport layer, where validation naturally happens. Descripex's job is to *describe*, not *enforce*. Will revisit if someone asks for it.

**Task 17 — Generate llms.txt from Manifest (rejected):** ex_doc v0.40+ already generates `llms.txt` from `@doc` text, and `api()` generates rich `@doc` text. Every Descripex-annotated library already gets llms.txt via `mix docs`. App-specific llms.txt correctly lives in the app layer, not the library.

**Task 18 — Generate OpenAPI 3.1 from Manifest (rejected):** OpenAPI describes HTTP APIs (methods, paths, request/response bodies). Descripex describes Elixir function contracts — no concept of HTTP routing, methods, or status codes. The mapping requires app-specific context only the consuming app knows. Belongs in the app layer.

---

## Docs & Discoverability

> Consumer-facing docs polish — hexdocs navigation and onboarding for AI-agent consumers of descripex-powered libraries.

<!-- TASKS:BEGIN phase=9 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 25 | ⬜ | 🎁 **docs-discoverability** · Group ExDoc extras (AGENTS.md, CONSUMING.md) under groups_for_extras for clean hexdocs nav [D:1/B:3/U:3 → Eff:3.0] 🎯 |
| Task 26 | ⬜ | 🎁 **docs-discoverability** · Add a describe-from-manifest onboarding cookbook section to CONSUMING.md [D:2/B:4/U:4 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

---

## Shipped

### v0.6.0 — JSONSpec Integration + MCP Tools

> `schema:` on params/opts/returns compiles to JSON Schema. `Descripex.MCP.tools/1` converts annotated modules into MCP tool definitions. `mix descripex.manifest` exports JSON manifests to disk. See [CHANGELOG.md](CHANGELOG.md#060---2026-03-29).

<!-- TASKS:BEGIN phase=7 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-7-v0-6-0-jsonspec-integration-mcp-tools).
<!-- TASKS:END -->

### v0.5.3 — JSON-Serializable Manifest Errors

> `Manifest.build/1` normalizes atom/tuple errors to JSON-safe maps. See [CHANGELOG.md](CHANGELOG.md#053---2026-03-26).

<!-- TASKS:BEGIN phase=6 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-6-v0-5-3-json-serializable-manifest-errors).
<!-- TASKS:END -->

### v0.5.2 — Multi-Arity Hints Root Cause Fix

> `__before_compile__` injects hints into the compiler's internal doc table for every arity. See [CHANGELOG.md](CHANGELOG.md#052---2026-03-15).

<!-- TASKS:BEGIN phase=5 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-5-v0-5-2-multi-arity-hints-root-cause-fix).
<!-- TASKS:END -->

### v0.5.1 — Multi-Arity Hints Fix

> `Manifest.build/1` uses `__api__/0` as authoritative hints source for all arities. See [CHANGELOG.md](CHANGELOG.md#051---2026-03-15).

<!-- TASKS:BEGIN phase=4 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-4-v0-5-1-multi-arity-hints-fix).
<!-- TASKS:END -->

### v0.5.0 — Multi-Arity Support

> Param validation works across all arities, handling both true multi-arity and default-argument functions. See [CHANGELOG.md](CHANGELOG.md#050---2026-03-12).

<!-- TASKS:BEGIN phase=3 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-3-v0-5-0-multi-arity-support).
<!-- TASKS:END -->

### v0.4.1 — BEAM Docs Coexistence

> Manual `@doc` + `api()` coexistence, consumer discovery workflow. See [CHANGELOG.md](CHANGELOG.md#041---2026-02-25).

<!-- TASKS:BEGIN phase=2 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2-v0-4-1-beam-docs-coexistence).
<!-- TASKS:END -->

### v0.4.0 — Agent-Friendly Docs

> Errors, contract blocks, returns_example, moduledoc tables, composes_with, dogfooding. See [CHANGELOG.md](CHANGELOG.md#040---2026-02-25).

<!-- TASKS:BEGIN phase=1 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-v0-4-0-agent-friendly-docs).
<!-- TASKS:END -->
