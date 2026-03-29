# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/skills-awareness.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/web-command.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/documentation-guidelines.md
@~/.claude/includes/ai-coder-docs.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/agent-economy.md
@~/.claude/includes/elixir-patterns.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/library-design.md
@~/.claude/includes/meta-development.md

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
mix doctor                               # Enforce 100% docs/specs/moduledocs
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
| `Descripex.Describe` | Progressive disclosure — `describe/1-3` for library overview, module functions, and function detail |
| `Descripex.Discoverable` | Convenience macro — `use Descripex.Discoverable, modules: [...]` generates `describe/0-2` |

### The `api` Macro Options

| Option | Type | Description |
|--------|------|-------------|
| `params` | keyword list | Positional parameters — each has `kind`, `description`, optional `default`, optional `schema` |
| `opts` | keyword list | Keyword-style options — each has `type`, `description`, optional `default`, optional `schema` |
| `returns` | map | Return value — has `type`, `description`, optional `schema` |
| `returns_example` | any term | Concrete return example rendered in doc text and included in `@doc hints:` |
| `errors` | list (atoms and/or keyword descriptions) | Known error cases (e.g., `[:division_by_zero]`, `[not_found: "Record does not exist"]`, or mixed) |
| `composes_with` | list of atoms | Intra-module function composition references (e.g., `[:normalize, :persist]`) |

The `kind` field on params distinguishes `:value` (caller provides) from `:exchange_data` (must be fetched from external source).

The optional `schema` field accepts Elixir type syntax (e.g., `schema: float()`, `schema: [String.t()]`, `schema: :buy | :sell`) and compiles it to JSON Schema via [json_spec](https://hexdocs.pm/json_spec) at compile time. The resulting JSON Schema map appears in `hints.params.*.schema` — zero runtime cost.

### Compile-Time Validation

The `__before_compile__` hook enforces:
1. Every `api(:name, ...)` must have a matching `def name(...)` — raises `CompileError` otherwise
2. Declared param names must match actual function argument names (by position) — pattern-matched args (like `[]` or `_`) are skipped
3. Multi-clause and multi-arity functions are handled by collecting param names from ALL clauses across ALL arities — a declared name is valid if it matches ANY clause at that position
4. `composes_with` references must be atoms pointing to functions defined in the same module

### Test Architecture

Tests in `descripex_test.exs` use a `compile_and_fetch_docs/1` helper that dynamically compiles modules with `Code.compile_string/1` and extracts the Docs beam chunk. This avoids polluting the test namespace and allows testing compile-time validation errors with `assert_raise CompileError`. Modules are cleaned up in `after` blocks with `:code.purge/1` and `:code.delete/1`.

The `test/support/fixtures.ex` file (compiled via `elixirc_paths`) provides pre-compiled fixture modules for `ManifestTest` and `DescribeTest`. Fixtures include: `AnnotatedFixture` (Descripex-annotated), `PlainFixture` (plain module with `@doc` and `@doc false` functions), `V1.Funding` + `V2.Funding` (ambiguous short name testing), `GammaWalls` (multi-word CamelCase short name regression), and `NoDocs` (module with no meaningful docs).

`test_helper.exs` sets `Code.compiler_options(docs: true)` because ExUnit defaults to `docs: false`, and fixture modules need accessible `@doc`/`@moduledoc` metadata.

### BEAM Docs Tuple — @doc vs api() Slots

Each function's compiled doc is a 5-element tuple in the BEAM docs chunk:

| Element | Content | Written by |
|---------|---------|------------|
| 1 | `{:function, :name, arity}` | Compiler |
| 2 | Line number | Compiler |
| 3 | `["name(args)"]` signature | Compiler |
| 4 | `%{"en" => "..."}` doc text | `@doc "text"` |
| 5 | `%{hints: %{...}}` metadata | `@doc hints:` |

`api()` writes to **both** slot 4 (generated prose) and slot 5 (hints metadata). These slots are independent — they never collide. This means a user can write a manual `@doc` **after** `api()` and it overwrites only slot 4, while the hints in slot 5 survive untouched. Useful for bang variants or functions needing custom prose alongside structured metadata.

### ExDoc Compatibility

Earmark (ExDoc's markdown parser) treats `{...}` as Inline Attribute Lists (IAL). Since `api()` descriptions commonly contain Elixir return types like `{:ok, %{current, history}}`, Descripex escapes `{` → `\{` and `}` → `\}` in all user-provided description strings when generating `@doc` text. The `escape_doc/1` private helper handles this in four places: top-level description, param descriptions, opt descriptions, and returns description.

The raw (unescaped) descriptions are preserved in `@doc hints:` metadata — only the human-readable `@doc` text is escaped.

### Design Principles

- **Zero runtime deps**: Only Elixir stdlib
- **Pure library**: No GenServers, no state, no side effects
- **Generic**: Zero domain-specific logic — works for any Elixir project
- **Compile-time validation**: Catches param name mismatches and missing functions before runtime
- **Documentation gate**: `.doctor.exs` enforces 100% `@doc`, `@spec`, and `@moduledoc` coverage

## Git Commit Configuration

### Commit Message Format

**Format**: conventional-commits

#### Template
```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore
