# Descripex Roadmap

**Vision:** Make Descripex-annotated libraries fully discoverable and consumable by AI agents through llms.txt and structured documentation.

**Current version:** v0.3.1

---

## 🎯 Current Focus

**v0.4.0: Agent-Friendly Docs** — Closing the gap between `@doc hints:` metadata and what agents see in llms.txt.

> **The gap:** `api()` generates rich metadata into `@doc hints:`, but ex_doc's llms.txt pipeline only sees `@doc` text. Errors, structured contracts, and module overviews never reach agents consuming llms.txt.

### Summary

| # | Task | D/B | Priority | Status |
|---|------|-----|----------|--------|
| 1 | Add `## Errors` section to doc text | D:2/B:8 → 4.0 🎯 | ✅ |
| 2 | Extend `errors:` to accept keyword descriptions | D:2/B:5 → 2.5 🎯 | ✅ |
| 3 | Embed machine-readable contract block | D:4/B:9 → 2.25 🎯 | ⬜ |
| 4 | Add `returns_example` option | D:3/B:5 → 1.67 🚀 | ⬜ |
| 5 | Auto-generate `@moduledoc` function table | D:5/B:8 → 1.6 🚀 | ⬜ |
| 6 | Add `composes_with` option | D:4/B:4 → 1.0 📋 | ⬜ |

### Dependencies

- Task 2 extends Task 1 (do together or sequentially)
- Tasks 3, 4, 5, 6 are independent `[P]`

---

## Task Details

### Task 1: Add `## Errors` section to doc text [D:2/B:8 → 4.0] 🎯

Errors currently only flow to `@doc hints:` metadata via `build_hints/2`, never to `@doc` text. Add a `format_errors_section/1` helper and integrate it into `generate_doc/2` so that declared errors appear as a `## Errors` section in the rendered documentation.

**Success criteria:**
- [x] `@doc` text contains `## Errors` section with atom names when `errors:` provided
- [x] No `## Errors` section when `errors:` not provided
- [x] `EarmarkParser.as_ast/1` produces zero warnings on generated doc text
- [x] Existing tests still pass
- [x] New tests cover both presence and absence of errors section

### Task 2: Extend `errors:` to accept keyword descriptions [D:2/B:5 → 2.5] 🎯

Support both `[:atom]` (current) and `[atom: "description"]` formats for the `errors:` option. Backward compatible — plain atoms render as before, keyword pairs render with descriptions.

**Success criteria:**
- [x] `errors: [:not_found]` still works (backward compatible)
- [x] `errors: [not_found: "Record does not exist"]` renders description in doc text
- [x] Mixed format `errors: [:timeout, not_found: "Record does not exist"]` works
- [x] Both formats flow correctly to `@doc hints:` metadata
- [x] Tests verify both formats in doc text and hints

### Task 3: Embed machine-readable contract block [D:4/B:9 → 2.25] 🎯

Append a fenced `elixir` code block with a `# descripex:contract` sentinel to each function's `@doc` text. The block contains the hints map minus `:description` — giving agents a parseable contract alongside the human-readable docs.

**Design decisions:**
- Fenced `elixir` code block — natural for ecosystem, Earmark renders as `<pre><code>`
- `# descripex:contract` sentinel — agents search for this marker to extract structured data
- Earmark does NOT process content inside fenced blocks as IAL, so curly braces are safe (no escaping needed)
- Contains: params (with kinds), returns, errors, opts — everything from hints except description

**Success criteria:**
- [ ] `@doc` text contains fenced code block with `# descripex:contract` sentinel
- [ ] Block contains param kinds, returns, errors (all hint data except description)
- [ ] `EarmarkParser.as_ast/1` produces zero warnings
- [ ] Contract block appears after human-readable sections
- [ ] Tests verify contract content is parseable

### Task 4: Auto-generate `@moduledoc` function table [D:5/B:8 → 1.6] 🚀

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

### Task 5: Add `returns_example` option [D:3/B:5 → 1.67] 🚀

New `returns_example` option for `api()` that accepts a concrete return value example. Rendered in both doc text (as a code block) and in `@doc hints:` metadata.

**Success criteria:**
- [ ] `returns_example: {:ok, %{rate: 10.95}}` renders in doc text as example
- [ ] Example appears in `@doc hints:` metadata
- [ ] Works alongside existing `returns:` option
- [ ] Optional — no example rendered when not provided
- [ ] Tests verify presence in doc text and hints

### Task 6: Add `composes_with` option [D:4/B:4 → 1.0] 📋

New `composes_with` option declaring data flow between functions. For v1, intra-module only — references must be function names within the same module.

**Success criteria:**
- [ ] `composes_with: [:other_func]` declares composition relationship
- [ ] Referenced functions validated at compile time (must exist in module)
- [ ] Renders `## Composes With` section in doc text
- [ ] Flows to `@doc hints:` metadata
- [ ] Tests verify compile-time validation and doc rendering

---

## Verification (All Tasks)

After implementing each task:

1. `mix test.json --quiet` — all tests pass
2. `mix format` — code formatted
3. `mix credo` — no new warnings
4. `mix dialyzer.json --quiet` — no new warnings
5. `mix docs` — regenerate docs
6. Check `doc/*.md` files — verify new sections appear in rendered markdown
7. Check `doc/llms.txt` — verify content flows through to agent-visible docs
