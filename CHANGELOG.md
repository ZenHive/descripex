# Changelog

All notable changes to this project are documented in this file.

## [0.6.0] - Unreleased

### Added
- Optional `schema:` field on `params` and `opts` declarations in `api/3`. Accepts Elixir type syntax (e.g., `schema: float()`, `schema: [String.t()]`, `schema: :buy | :sell`) and compiles it to JSON Schema via [json_spec](https://hexdocs.pm/json_spec) at compile time. The resulting JSON Schema map appears in `hints.params.*.schema` and `hints.opts.*.schema` — zero runtime cost.
- Optional `schema:` field on `returns:` map in `api/3`. Same Elixir type syntax, same JSONSpec conversion. Appears in `hints.returns.schema`. Completes the schema contract across params, opts, and returns.
- New dependency: `json_spec ~> 1.1` (zero transitive deps, compile-time only usage).
- `preprocess_schemas/1` in the `api/3` macro body walks param/opt keyword lists and the returns map AST, converting `schema:` type AST to JSON Schema maps via `JSONSpec.convert/1` before the `quote` block.

### Key decisions
- Named the field `schema:` (not `type:`) to avoid collision with the existing `type:` field on opts declarations and to clearly signal "JSON Schema output."
- Conversion happens in the macro body (before `quote`) because type expressions like `float()` are only meaningful as AST — they can't survive `unquote` evaluation.
- Returns maps at macro time are AST (`{:%{}, meta, pairs}`), handled by `maybe_convert_returns_schema/1`. No changes needed downstream — `build_hints`, `Manifest.build`, `Describe.describe`, and the contract block all pass the returns map through unchanged.
- Backwards compatible: params/opts/returns without `schema:` are unchanged; no `schema` key appears in their hints.

### Tests
- Added `describe "schema option"` block in `descripex_test.exs`: basic params, opts, returns, complex types (maps, lists, enums), backwards compatibility, `__api__/0` output, and contract block inclusion.
- Added `SchemaFixture` in `test/support/fixtures.ex` with `schema:` on params, opts, and returns.
- Added manifest tests: schema in hints for params, opts, and returns; JSON serialization safety.
- Added describe tests: Level 3 detail includes param, opt, and returns schemas.

## [0.5.3] - 2026-03-26

### Fixed
- `Manifest.build/1` now produces fully JSON-serializable output when `api()` errors use `{atom, description}` tuples or plain atoms. Previously, `Jason.encode!/1` raised `Protocol.UndefinedError` on tuple values. Errors are now normalized to maps: `:timeout` → `%{name: "timeout"}`, `{:not_found, "desc"}` → `%{name: "not_found", description: "desc"}`.

### Tests
- Added `ErrorsFixture` with mixed error formats (plain atoms + tuples)
- Added JSON serialization safety tests asserting `Jason.encode/1` succeeds on manifest output
- Added error normalization assertion verifying map structure

## [0.5.2] - 2026-03-15

### Fixed
- **Root cause fix**: `@doc hints:` metadata now propagates to ALL arities of multi-arity functions in the BEAM docs chunk. Previously, hints only landed on the first arity (the def immediately after `api()`). Now `__before_compile__` injects hints into the compiler's internal doc table for every arity before the BEAM chunk is assembled. External consumers using `Code.fetch_docs/1` see hints on all arities.

### Tests
- Updated multi-arity BEAM docs test to assert hints ARE present on all arities (was asserting absence)
- Added 3-arity function test matching the original bug report reproduction case

## [0.5.1] - 2026-03-15

### Fixed
- `Manifest.build/1` now includes hints on ALL arities of multi-arity functions. Previously, `@doc hints:` only landed on the first arity in the BEAM docs chunk, so `Manifest` missed hints on higher arities. Now uses `__api__/0` as the authoritative hints source when available.

### Tests
- Added multi-arity hints propagation tests for `Manifest.build/1`:
  - True multi-arity fixture (`MultiArityFixture`) verifies both arities have hints
  - Real-world regression: `Descripex.Describe` (3 arities) all have hints in manifest
- Added BEAM docs chunk behavior tests documenting the known limitation (hints on first arity only)
- Added `__api__/0` correctness test for true multi-arity functions

## [0.5.0] - 2026-03-12

### Added
- Multi-arity function support: `api()` now validates param names across ALL arities of a function, not just the max arity. This fixes validation failures on functions with multiple arities where different arities have different param names at the same position (e.g., `def foo(list)` and `def foo(map, key)`).
- Param validation now accepts a declared name if it matches ANY clause at that position across all arities, handling both true multi-arity functions and functions with default arguments.

### Tests
- Added multi-arity validation tests:
  - Validates against matching arity clause (not just max arity)
  - Different param names at same position across arities compile successfully
  - `__api__/0` reports max arity for multi-arity functions
  - Functions with defaults still validate correctly

## [0.4.1] - 2026-02-25

### Added
- Documented BEAM docs tuple coexistence: manual `@doc` after `api()` overwrites doc text (slot 4) while hints metadata (slot 5) survives untouched. Enables rich custom prose alongside structured metadata.
- Added `SKILLS.md` — consumer guide for discovering and using descripex-powered libraries (detection, 3-level discovery workflow, alternative entry points, manifest).

### Tests
- Added tests for manual `@doc` coexistence with `api()`:
  - Verifies manual `@doc` after `api()` overwrites generated prose but preserves hints
  - Verifies `api()` alone populates both slots (control case)

## [0.4.0] - 2026-02-25

### Added
- Added `## Errors` section generation in `@doc` text when `errors:` is present in `api/3`.
- Added support for rendering `errors:` entries as:
  - atoms (`[:division_by_zero]`)
  - keyword descriptions (`[not_found: "Record does not exist"]`)
  - mixed lists (`[:timeout, not_found: "Record does not exist"]`)
- Added machine-readable contract block output to generated `@doc` text:
  - fenced `elixir` block
  - `# descripex:contract` sentinel
  - serialized hints payload excluding `:description`
- Added `returns_example` option to `api/3`.
  - Renders under `## Returns` as `### Example` plus a fenced `elixir` code block.
  - Included in `@doc hints:` metadata as `:returns_example`.
  - Included in the machine-readable contract block payload.
- Added automatic module-level `## API Functions` table generation in `__before_compile__/1`.
  - Appends to existing `@moduledoc` text.
  - Preserves moduledoc metadata (including `namespace:`).
  - Handles `@moduledoc false` (no changes) and `@moduledoc nil` (table-only text).
- Added `composes_with` option to `api/3`.
  - Declares function composition relationships as intra-module function names.
  - Renders `## Composes With` section in generated `@doc` text.
  - Included in `@doc hints:` metadata as `:composes_with`.
  - Included in the machine-readable contract block payload.
- Added strict Doctor configuration in `.doctor.exs` with 100% thresholds for:
  - module-level `@doc` coverage
  - module-level `@spec` coverage
  - overall `@doc`, `@spec`, and `@moduledoc` coverage
- Added documented/spec'd `Descripex.__api__/0` and `Descripex.__api__/1` for library-module introspection.
- **Dogfooding**: Descripex now describes itself:
  - `Descripex.Manifest` uses `use Descripex` + `api(:build, ...)` for self-describing introspection.
  - `Descripex.Describe` uses `use Descripex` + `api(:describe, ...)` covering all 3 arities.
  - `Descripex` uses `use Descripex.Discoverable, modules: [Descripex.Manifest, Descripex.Describe]` — `Descripex.describe()` returns a progressive-disclosure overview of the library itself.

### Tests
- Added coverage for:
  - errors section presence and absence in generated docs
  - atom, keyword, and mixed `errors:` formatting
  - curly-brace escaping in keyword error descriptions
  - zero-warning Earmark parsing for generated docs with errors
  - contract sentinel presence and placement after human-readable sections
  - parseable contract payload with params/opts/returns/errors and no `description` field
  - `returns_example` rendering with `returns:`, example-only behavior without `returns:`, and no-example regression
  - moduledoc table generation with:
    - append behavior for existing moduledoc text
    - namespace metadata preservation
    - `@moduledoc false` unchanged behavior
    - `@moduledoc nil` table generation
  - composes_with behavior with:
    - doc section rendering
    - hints and contract payload inclusion
    - compile-time validation for existing same-module functions
    - compile-time errors for missing and non-atom references
  - `Descripex.__api__/0` and `Descripex.__api__/1` behavior on the root module
  - Dogfooding self-description:
    - `Descripex.__descripex_modules__/0` returns annotated module list
    - `Descripex.describe/0` Level 1 overview of Manifest and Describe
    - `Descripex.describe/1` Level 2 for `:manifest` and `:describe`
    - `Descripex.describe/2` Level 3 detail with params/returns/returns_example
    - `Manifest.__api__/0` and `Describe.__api__/0` introspection
    - Manifest.build dogfooding for both self-describing modules
