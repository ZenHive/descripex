# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/skills-awareness.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/task-writing.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/documentation-guidelines.md
@include ~/.claude/includes/agent-economy.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md
@include ~/.claude/includes/elixir-setup.md
@include ~/.claude/includes/ex-unit-json.md
@include ~/.claude/includes/dialyzer-json.md
@include ~/.claude/includes/library-design.md

## Project Overview

**descripex** is a self-describing API declaration library for Elixir. It provides a macro system that generates documentation, machine-readable hints metadata, and runtime introspection from a single `api()` declaration.

- **App name**: `:descripex`
- **Module namespace**: `Descripex.*`
- **Hex**: https://hex.pm/packages/descripex
- **Docs**: https://hexdocs.pm/descripex
- **GitHub**: https://github.com/ZenHive/descripex
- **Runtime deps**: Zero Hex deps
- **Elixir**: `~> 1.18`

## Commands

```bash
mix test.json --quiet                    # Run tests (AI-friendly output)
mix test.json --quiet --failed           # Re-run only previously failed tests
mix dialyzer.json --quiet                # Type checking
mix credo                                # Static analysis
mix format                               # Format code (Styler plugin)
mix test.json test/descripex_test.exs --quiet  # Run a single test file
```

## Architecture

### How It Works (Data Flow)

```
api(:func, "desc", opts)          # 1. Macro call at compile time
  ├→ @doc (human-readable)        # 2. Generates formatted doc string
  ├→ @doc hints: %{...}           # 3. Emits machine-readable metadata
  └→ @descripex_api_declarations  # 4. Accumulates for __before_compile__

__before_compile__                # 5. Fires after all defs are collected
  ├→ validate_declaration!()      # 6. Ensures def exists, param names match
  └→ generates __api__/0, __api__/1  # 7. Runtime introspection functions

Descripex.Manifest.build(modules) # 8. Walks modules via Code.fetch_docs/1
  └→ assembles JSON-serializable map  #    + Code.Typespec.fetch_specs/1
```

### Module Structure

| Module | Purpose |
|--------|---------|
| `Descripex` | Main macro module (`use Descripex`, `api/2`, `api/3`) |
| `Descripex.Manifest` | Introspects modules via `Code.fetch_docs/1` to build JSON-serializable API manifests |

### The `api` Macro Options

| Option | Type | Description |
|--------|------|-------------|
| `params` | keyword list | Positional parameters — each has `kind`, `description`, optional `default` |
| `opts` | keyword list | Keyword-style options — each has `type`, `description`, optional `default` |
| `returns` | map | Return value — has `type` and `description` |
| `errors` | list of atoms | Known error cases (e.g., `[:division_by_zero]`) |

The `kind` field on params distinguishes `:value` (caller provides) from `:exchange_data` (must be fetched from external source).

### Compile-Time Validation

The `__before_compile__` hook enforces:
1. Every `api(:name, ...)` must have a matching `def name(...)` — raises `CompileError` otherwise
2. Declared param names must match actual function argument names (by position) — pattern-matched args (like `[]` or `_`) are skipped
3. Multi-clause functions are handled by finding named params across all clauses

### Test Architecture

Tests in `descripex_test.exs` use a `compile_and_fetch_docs/1` helper that dynamically compiles modules with `Code.compile_string/1` and extracts the Docs beam chunk. This avoids polluting the test namespace and allows testing compile-time validation errors with `assert_raise CompileError`. Modules are cleaned up in `after` blocks with `:code.purge/1` and `:code.delete/1`.

The `test/support/fixtures.ex` directory (compiled via `elixirc_paths`) provides pre-compiled fixture modules for `ManifestTest`.

`test_helper.exs` sets `Code.compiler_options(docs: true)` because ExUnit defaults to `docs: false`, and fixture modules need accessible `@doc`/`@moduledoc` metadata.

### Design Principles

- **Zero runtime deps**: Only Elixir stdlib
- **Pure library**: No GenServers, no state, no side effects
- **Generic**: Zero domain-specific logic — works for any Elixir project
- **Compile-time validation**: Catches param name mismatches and missing functions before runtime

## Git Commit Configuration

### Commit Message Format

**Format**: conventional-commits

#### Template
```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore
