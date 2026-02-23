# Repository Guidelines

## Project Structure & Module Organization
`descripex` is an Elixir library (not a Phoenix app). Core code lives in `lib/`:
- `lib/descripex.ex` contains the main macro API (`use Descripex`, `api/3`).
- `lib/descripex/manifest.ex` contains manifest building/introspection logic.

Tests are in `test/`:
- `test/descripex_test.exs` and `test/descripex/manifest_test.exs` cover macro behavior and manifest output.
- `test/support/` holds shared fixtures/helpers.

Project metadata and tooling are in `mix.exs` and `.formatter.exs`.

## Build, Test, and Development Commands
- `mix deps.get` - fetch dependencies.
- `mix compile` - compile library code.
- `mix test` - run ExUnit tests.
- `mix test.json` - run tests with machine-readable JSON output.
- `mix format` - format code using Elixir formatter + Styler plugin.
- `mix format --check-formatted` - CI-style formatting check.
- `mix credo` - static code checks.
- `mix dialyzer` / `mix dialyzer.json` - type analysis (plain or JSON output).
- `mix docs` - generate HexDocs locally.

## Coding Style & Naming Conventions
Use standard Elixir style: 2-space indentation, clear function names, and pattern matching in function heads where appropriate. Keep module names under the `Descripex.*` namespace and use snake_case filenames (for example, `manifest.ex`).

Always run `mix format` before opening a PR. Prefer explicit, readable code over clever metaprogramming beyond the library’s macro surface.

## Testing Guidelines
Use ExUnit (`use ExUnit.Case, async: true` where safe). Name test files `*_test.exs` and group behavior with `describe` blocks. Add regression tests for every bug fix and tests for macro validation paths (success + failure cases).

No strict coverage gate is currently configured; maintain strong coverage for public macros and manifest generation paths.

## Commit & Pull Request Guidelines
Current history follows Conventional Commit style:
- `feat(descripex): ...`
- `fix(package): ...`
- `docs: ...`
- `chore(package): ...`

PRs should include:
- concise summary of behavior changes,
- linked issue (if applicable),
- test evidence (`mix test`, plus lint/type checks when relevant).
