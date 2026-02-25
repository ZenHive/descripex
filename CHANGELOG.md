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

### Tests
- Added coverage for:
  - errors section presence and absence in generated docs
  - atom, keyword, and mixed `errors:` formatting
  - curly-brace escaping in keyword error descriptions
  - zero-warning Earmark parsing for generated docs with errors
  - contract sentinel presence and placement after human-readable sections
  - parseable contract payload with params/opts/returns/errors and no `description` field
