# Descripex Roadmap

**Vision:** Make Descripex-annotated libraries fully discoverable and consumable by AI agents through llms.txt and structured documentation.

**Current version:** v0.5.1
**Completed work details:** See [CHANGELOG.md](CHANGELOG.md).

---

## Backlog

No tasks in backlog.

---

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
