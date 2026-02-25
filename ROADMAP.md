# Descripex Roadmap

**Vision:** Make Descripex-annotated libraries fully discoverable and consumable by AI agents through llms.txt and structured documentation.

**Current version:** v0.3.1
**Completed work details:** See [CHANGELOG.md](CHANGELOG.md).

---

## 🎯 Current Focus

**v0.4.0: Agent-Friendly Docs** — Closing the gap between `@doc hints:` metadata and what agents see in llms.txt.

### Summary

| # | Task | D/B | Priority | Status |
|---|------|-----|----------|--------|
| 1 | Add `## Errors` section to doc text | D:2/B:8 → 4.0 🎯 | ✅ ([changelog](CHANGELOG.md#040---2026-02-25)) |
| 2 | Extend `errors:` to accept keyword descriptions | D:2/B:5 → 2.5 🎯 | ✅ ([changelog](CHANGELOG.md#040---2026-02-25)) |
| 3 | Embed machine-readable contract block | D:4/B:9 → 2.25 🎯 | ✅ ([changelog](CHANGELOG.md#040---2026-02-25)) |
| 4 | Add `returns_example` option | D:3/B:5 → 1.67 🚀 | ✅ ([changelog](CHANGELOG.md#task-4-add-returns_example-option)) |
| 5 | Auto-generate `@moduledoc` function table | D:5/B:8 → 1.6 🚀 | ✅ ([changelog](CHANGELOG.md#task-5-auto-generate-moduledoc-function-table)) |
| 6 | Add `composes_with` option | D:4/B:4 → 1.0 📋 | ⬜ |

### Dependencies

- Task 2 extends Task 1 (do together or sequentially)
- Tasks 5, 6 are independent `[P]`

---

## Pending Task Details

Task 5 complete. See [CHANGELOG.md](CHANGELOG.md#task-5-auto-generate-moduledoc-function-table).

### Task 6: Add `composes_with` option [D:4/B:4 → 1.0] 📋

New `composes_with` option declaring data flow between functions. For v1, intra-module only — references must be function names within the same module.

**Success criteria:**
- [ ] `composes_with: [:other_func]` declares composition relationship
- [ ] Referenced functions validated at compile time (must exist in module)
- [ ] Renders `## Composes With` section in doc text
- [ ] Flows to `@doc hints:` metadata
- [ ] Tests verify compile-time validation and doc rendering
