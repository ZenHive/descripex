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
| 4 | Add `returns_example` option | D:3/B:5 → 1.67 🚀 | ⬜ |
| 5 | Auto-generate `@moduledoc` function table | D:5/B:8 → 1.6 🚀 | ⬜ |
| 6 | Add `composes_with` option | D:4/B:4 → 1.0 📋 | ⬜ |

### Dependencies

- Task 2 extends Task 1 (do together or sequentially)
- Tasks 4, 5, 6 are independent `[P]`

---

## Pending Task Details

### Task 4: Add `returns_example` option [D:3/B:5 → 1.67] 🚀

New `returns_example` option for `api()` that accepts a concrete return value example. Rendered in both doc text (as a code block) and in `@doc hints:` metadata.

**Success criteria:**
- [ ] `returns_example: {:ok, %{rate: 10.95}}` renders in doc text as example
- [ ] Example appears in `@doc hints:` metadata
- [ ] Works alongside existing `returns:` option
- [ ] Optional — no example rendered when not provided
- [ ] Tests verify presence in doc text and hints

### Task 5: Auto-generate `@moduledoc` function table [D:5/B:8 → 1.6] 🚀

In `__before_compile__`, append a `## API Functions` markdown table to the user's `@moduledoc`. Shows function name, arity, description, and param kinds.

**Design decisions:**
- Always generated — it's a function summary, useful for humans and agents
- MUST preserve existing moduledoc text AND metadata (especially `namespace:`)
- Handle edge cases: moduledoc is `nil`, `false`, or `{line, text}` tuple

**CRITICAL:** `@moduledoc` can carry metadata (e.g., `namespace:`). When appending to moduledoc text, the metadata must be preserved. Read current moduledoc state via `Module.get_attribute/2` and rewrite only the text portion.

**Success criteria:**
- [ ] `@moduledoc` text contains `## API Functions` table
- [ ] Table shows name, arity, description, param kinds for each `api()` declaration
- [ ] `namespace:` metadata is still preserved (regression test against existing namespace test)
- [ ] `@moduledoc false` is left alone (no table appended)
- [ ] `nil` moduledoc gets just the table
- [ ] Tests verify table content and metadata preservation

### Task 6: Add `composes_with` option [D:4/B:4 → 1.0] 📋

New `composes_with` option declaring data flow between functions. For v1, intra-module only — references must be function names within the same module.

**Success criteria:**
- [ ] `composes_with: [:other_func]` declares composition relationship
- [ ] Referenced functions validated at compile time (must exist in module)
- [ ] Renders `## Composes With` section in doc text
- [ ] Flows to `@doc hints:` metadata
- [ ] Tests verify compile-time validation and doc rendering
