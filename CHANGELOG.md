# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

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

### Task 4: Add `returns_example` option
- Status: Complete

### Task 5: Auto-generate `@moduledoc` function table
- Status: Complete

### Task 6: Add `composes_with` option
- Status: Complete
