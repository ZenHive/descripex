# Changelog

All notable changes to this project are documented in this file.

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
