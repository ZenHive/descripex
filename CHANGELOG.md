# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

## [0.4.0] - 2026-02-25

### Added
- Added `## Errors` section generation in `@doc` text when `errors:` is present in `api/3`.
- Added support for rendering `errors:` entries as:
  - atoms (`[:division_by_zero]`)
  - keyword descriptions (`[not_found: "Record does not exist"]`)
  - mixed lists (`[:timeout, not_found: "Record does not exist"]`)

### Changed
- Extended API option documentation in `CLAUDE.md` for `errors` to reflect atom, keyword, and mixed formats.
- Updated `ROADMAP.md` status and success criteria for completed Tasks 1 and 2.

### Tests
- Added coverage for:
  - errors section presence and absence in generated docs
  - atom, keyword, and mixed `errors:` formatting
  - curly-brace escaping in keyword error descriptions
  - zero-warning Earmark parsing for generated docs with errors

### Verification
- `mix test`
- `mix format --check-formatted`
- `mix credo`
- `mix test.json --quiet`
- `mix dialyzer.json --quiet`
