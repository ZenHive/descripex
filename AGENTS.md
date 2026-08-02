<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- @-import: ~/.claude/includes/critical-rules.md -->
## 🚨 ANSWER IN SHORT TEXT — ALWAYS

Short, pointed text — explanation, proposal, pushback, summary alike. Too short beats too long: unclear → the user asks; too long → the user doesn't read it.

## 🚨 BE A REAL PARTNER, NOT A YES-SAYER

- Challenge what seems wrong, risky, or suboptimal. Not every request is a good idea.
- Flawed approach → "I'd push back because…". Better alternative → present it with reasoning.
- Scope too big *or too small* → flag it.
- Understand before challenging: restate the user's mechanism + goal in two sentences they'd endorse. Can't → ask, don't challenge.
- Partial understanding → questions only. "Seems wrong" without naming what you understood is noise.
- "Not how software is normally built" is not an objection.
- ≤3 sentences. Direct, not combative.
- Made your case and the user still wants it → commit fully. Pushback ≠ blocking.

### Think As an AI, Not Only As a Developer

| Kind | Belongs in |
|---|---|
| **Judgment** — interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match | an AI. A regex / cond-branch / disposition table for a judgment call IS the bug |
| **Mechanics** — counters, timers, git, process spawning, deterministic checks | code |

Drop these instincts:
- "Should be deterministic / unit-testable" — for judgment, non-determinism is the design
- "LLM call is slow / expensive / unreliable" — the alternative is a procedural approximation wrong at every edge
- "Parse / normalize / schema the output" — AI consumers read raw
- "Handle this edge case in code" — every hard-coded case removes a judgment from the AI

Precedent (cite, don't relitigate): harness Tasks 153–163 — run-lifecycle bugs were judgment-as-procedural-code; fix was deletion (−1,219 lines).

## 🚨 SURFACE THE OVERRIDE — DON'T DECIDE SILENTLY

Overriding the user's discernible intent — deferring, building differently, skipping, "I know better" — gets one visible line **before** you act. Never act silently and rationalize after.

- Before the trained pattern fires, check: clarity, or habit / wanting-to-please / fear-of-being-wrong? Only clarity earns a silent decision.
- Surface ≠ block: "doing X instead of Y because Z — say if wrong", then proceed. Don't gate on a question.
- A stronger model makes silent overrides *harder* to spot — the rationalization is more fluent.

## 🚨 NEVER START THE PHOENIX SERVER

Always already running. Never `mix phx.server`. Assume localhost:4000. To verify behavior, ask the user to check the browser.

## 🚨 ALWAYS WRITE TESTS

Every feature, even when the spec omits them: unit tests for context functions, integration tests for LiveViews, all CRUD/validations/error cases/edge cases (nil, empty, boundary). No tests → not complete.

## 🚨 AGAINST AN API, THE PROVIDER-OWNED CONTRACT IS THE AUTHORITY

Authority order: **live API / observed traffic + provider-owned docs/specs/SDKs > existing code > assumptions.** Third-party clients, aggregators, wrappers, reference impls (incl. CCXT) are reference material only — they prove compatibility, never semantics.

- Hit the live API FIRST, then mock only what you've already seen. A mock encodes your guess; it passes green while the real call 400s.
- Tidewave `project_eval` to explore → `@moduletag :integration` test to pin. Flunk on missing creds, never skip silently.
- Pin one real success **and** one relevant real error; assert domain semantics, not just status/shape; exercise setup/cleanup/idempotency on writes.
- Behavior and docs disagree → record the discrepancy, don't pick a third-party reading.
- Can't reach the API → say so and `flunk`. Never a mock that ratifies a guess.
- A green claim names the independent evaluator + durable evidence (harness run, CI URL, review artifact). Self-report is not verification.

## 🚨 RAISE COVERAGE BEFORE MUTATING

Before any code-changing task on an existing module, its `mix test.json --cover` must be at tier — **≥80%** standard, **≥95%** critical (money, signing, crypto, low-level encoders, security-sensitive parsers; when in doubt, critical). Below tier → write the missing tests first, in this task.

1. `mix test.json --cover --quiet --output /tmp/cov.json`
2. `jq '.coverage.modules[] | select(.module == "MyApp.Foo")' /tmp/cov.json`
3. Below tier → cover the uncovered lines, even ones you didn't come to change. Then mutate.

Exempt: doc-only edits, formatting/alias reordering, pure renames, typo fixes in strings/messages.

## 🚨 NEVER HIDE TEST FAILURES

A test that passes on every outcome is lying. Never `{:error, _} -> assert true`, never a catch-all `{:error, _} -> :ok`, never `IO.puts` + `assert true`.

```elixir
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :insufficient_balance} -> :ok          # this specific error is expected
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

- Don't know what error to expect → don't write the test yet. Explore via Tidewave, then assert.
- Integration tests: never `:skip` on missing credentials. Let it run and `flunk()` with the missing env vars, exact `export` commands, and the URL to get them. "0 failures" from 0 tests is a lie.

## 🚨 FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH

Hook fires → fix → re-run → stage. No planning around it, no asking, no discussing whether to. Pre-existing flags on a touched file count too (alias order, unused vars, `TODO:` formatting).

- Scope is only the files your change touched, not the project.
- Generated files → fix the generator.
- Never move the fix to ROADMAP or a follow-up. This commit.
- Don't re-run a check the hook just ran on the same files. Full-suite re-runs earn their cost only before a PR/merge, after `mix deps.get`, after a branch switch, or on request.

## 🚨 READ TO THE ANSWER — DON'T USE THE RUNNER AS AN ORACLE

Reason to the fix by reading code; run once to CONFIRM, not to DISCOVER.

- Read the code path before the test that exercises it.
- Treat a failure as a SURVEY: enumerate every plausible cause from output + one read, fix in a batch, run once.
- Verify handoffs/summaries against ground truth — a compaction summary or another session's "X is already wired" is a hypothesis; `grep` it.
- Flaky terminal → sequential and simple: one command → file → Read. No parallel batches of dependent calls.

## 🚨 FLAKY TESTS & TEST-RUN TOKEN ECONOMY

- 1–2 failures out of hundreds, in a file your diff didn't touch → flaky **hypothesis**. Re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed. One isolated re-run is the whole investigation.
- NEVER `Process.sleep` to fix a flake. Use `assert_receive`/`refute_receive`, `Process.monitor` + `{:DOWN, …}`, `start_supervised!`, or poll-until-condition.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB. Always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## 🚨 NO PSEUDO-RIGOROUS HEDGING

You have no consumer telemetry, no usage counts, no demand signal. Don't gate user-requested work behind evidence you cannot obtain. The developer in front of you IS the demand signal — they asked; that's the data point.

STOP if about to write:
- "Demand for X is unproven"
- "We should wait until…"
- "Is this widely needed?"
- "Only worth doing if a Nth+ case is imminent"
- "Bet on usage data before building"

**A legitimate "wait" names an external blocker with an unblock path** — a missing dep, an unreleased upstream, an unactivated market. **"Nobody has asked yet" is not a trigger.** Neither is "it's additive, cheap to add later."

Instead: name actual technical risks ("the macro grows more knobs than the duplication it removes"), cite concrete precedents, or score the task honestly low. Honest framing: *"I don't know if you'll use this 12 more times — that's your call."*

Applies to task `body` fields and score justifications too — "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to" inflate B/U the same way. Required: a concrete named reason, or an honest low score.

## Git Commit / Push / PR-Create — Allowed by Default

Commit, push, open PRs without asking when the task calls for it. Announce in one line, then act.

Only residual gate: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) — confirm first, because it's irreversible.

### 🚨 STAGE PATH-SCOPED — THE WORKING TREE IS SHARED

- NEVER `git add -A` / `git add .` / `git commit -a`. Stage explicitly (`git add <path>`) or commit path-scoped (`git commit <path>`).
- Verify before every commit: `git diff --cached --name-only`. A path you didn't touch is someone else's.
- Pre-commit hook trips on a foreign file → path-scoped-stash only their paths (`git stash push -- <paths>`), commit yours, `git stash pop`, re-stage what was staged before. Never format or fix work that isn't yours to clear a hook.
- Untracked files you didn't create: leave them. No `-u` stash, no `add`.

## 🚨 NEVER BROADCAST AN UNPATCHED VULNERABILITY IN A COMMITTED FILE

A committed file is a public file — and permanent in git history. Exploit-actionable detail (attack mechanism, trigger value, PoC, unpublished GHSA/CVE id) never goes into `roadmap/tasks.toml`, `ROADMAP.md`, `CHANGELOG.md`, code comments, or commit messages.

- **Open + undisclosed → out of git.** Track in a private draft GitHub Security Advisory (`gh api repos/<org>/<repo>/security-advisories -X POST`, draft; `vulnerabilities[]` needs ecosystem + package + `vulnerable_version_range`). One per issue, full detail there and only there.
- **Fixed AND advisory published → fine to reference.** The gate is both, not either.
- **Need to schedule the work?** File the rmap task with a sanitized body: `"harden Tempo fee-payer gas bounds — see private advisory <id>"`. Never the mechanism.
- **Embargo window:** commit messages and CHANGELOG describe the shape of the fix, not the hole.
- **Inbound reports hide in one place:** privately-reported vulns appear ONLY under Security → Advisories (`gh api repos/<org>/<repo>/security-advisories`) — not Dependabot, not code/secret scanning, not the notifications inbox. Always query it; act on `triage` and `draft`.
- **Public ledgers carry only ✓ closed / 📋 tracked rows** plus a generic open-item count. Never an enumerated map of unpatched weaknesses.
- **On fix:** patch → release → publish the advisory naming the patched version, same day.
- Already committed = already leaked. Redact now and treat git history as compromised (rotate/patch), don't just stop going forward.

## Shell Safety

`rm` is permitted. Before an irreversible delete, glance at the target — no unexpanded `$VAR`, no wildcard catching more than you mean, not a path you didn't create. `git rm` for tracked files keeps the removal in the diff.

## 🚨 NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS

Never without explicit consent: `mix deps.clean` (incl. `--all`), `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`, `mix clean`.

Instead: compile error → retry `mix compile` / `mix test`. Specific dep → `mix deps.compile <dep> --force`. Most "corrupt cache" issues are transient.

## 🚨 NO SCOPE-SEQUENCING QUALIFIERS IN DURABLE ARTIFACTS

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners. They metastasize and become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Elsewhere describe what the system IS: "Coverage: Robinhood Chain tokenized equities", not "starting with Robinhood Chain".

## 🚨 Integrity and Accuracy

- Never fabricate information, experience, metrics, timelines, or stats.
- Distinguish codebase observation / general knowledge / best practice / speculation.
- No false authority: no "we learned" without repo evidence, no "after X years in production".
- Uncertain → say so, give ranges over false precision, suggest a validation path.
- Trace sources: "Based on the code in file.ex…", "According to docs/FILE.md…", "Common practice in Elixir…".

## 🚨 RESEARCH BEFORE ASSERTING ON NICHE TECHNICAL CLAIMS

Outside reliable training coverage, research proactively — unasked. WebFetch when the canonical URL is known, WebSearch to find one. **Cite what you fetched.**

Research:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never claim byte order, length-prefix, padding, or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; one impl's behavior can be a bug, agreement across two is the spec in practice.

Don't research: pure Elixir/OTP, stdlib, mainstream Phoenix/LiveView/Ecto/Ash, generic REST/HTTP/JSON/SQL/shell, anything in the codebase or an imported CLAUDE.md.

Fetch fails or is ambiguous → say so and lower confidence. Never fall back to "well, I think…" silently.

## 🚨 NO EVASION — SIT WITH THE HARD THING

Hitting a wall → silently moving to easier work is the failure. Stay with it; say "this is hard because X".

Don't use without explicit user approval:
- "let's move on to", "we can defer this", "skip this for now", "let's come back to this later", "let's table this"
- "to keep things simple, I'll skip", "for brevity, I won't", "that's out of scope", "not strictly necessary"
- "that should be enough", "the rest is straightforward", "I'll leave the rest as an exercise"
- "you might want to", "you could manually", "you'll need to handle"

- Blocked → name it: "blocked on X because Y. Options: A, B, C."
- Never a silent workaround. Tempted to add a fallback/nil-guard for missing data → should it come from upstream? Then stop and report.
- Must move on → leave a tracked TODO, not a silent gap.


<!--
  Eager floor only (Opus 4.8 selective-load — see ~/.claude/setup-guide.md § Elixir Library).
  Everything else is skill-on-demand and auto-loads via the elixir / task-driver / review plugins:
    worktree-workflow → workflow:git-worktrees      rmap → tasks:rmap
    task-prioritization → tasks:roadmap-planning     workflow-philosophy → workflow:workflow-philosophy
    task-writing → tasks:task-writing                ex-unit-json/dialyzer-json/code-style/
    development-commands/development-philosophy → elixir:*
  Re-add an @-import here only if Opus is observed failing on that surface in this repo.
  delegation-rules / across-instances intentionally dropped (standalone library, not a delegation target).
-->

## Project Overview

**descripex** is a self-describing API declaration library for Elixir. It provides a macro system that generates documentation, machine-readable hints metadata, and runtime introspection from a single `api()` declaration.

- **App name**: `:descripex`
- **Module namespace**: `Descripex.*`
- **Hex**: https://hex.pm/packages/descripex
- **Docs**: https://hexdocs.pm/descripex
- **GitHub**: https://github.com/ZenHive/descripex
- **Runtime deps**: `json_spec ~> 1.1` (compile-time JSON Schema conversion)
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
mix descripex.manifest Module1 Module2   # Export JSON manifest to api_manifest.json
mix descripex.manifest --app my_app      # Auto-discover annotated modules in app
```

## Toolchain & check commands

Two gates, one a superset of the other:

- **`mix ci`** — the portable gate, and what `.github/workflows/harness.yml` runs:
  compile `--warnings-as-errors`, `format --check-formatted`, `credo --strict`,
  `doctor --raise`, `ex_dna --max-clones 0`, `reach.check --arch --smells`,
  `sobelow --skip --exit low`, `deps.audit` + advisory-database-present guard,
  `test.json --cover --cover-threshold 70`, `dialyzer`. Every step runs on a bare clone.
  The guard is load-bearing: `mix_audit` clones its advisory database at runtime and
  discards the clone's exit status, so a failed clone audits zero advisories and still
  exits 0.
- **`mix precommit.full`** — `advisory.fresh` + `ci` + `agents.check`. The two extra
  steps read the operator's home directory (`~/.local/share/…` advisory mirror,
  `~/.claude/includes/*.md` behind AGENTS.md's render), so they are host-local by
  nature and deliberately absent from `ci`. This is the merge bar and the harness
  reviewer's `check_command`.

`mix precommit` is the fast local loop (no dialyzer/coverage).

- **`mix test.json` / `mix dialyzer.json` emit JSON by design** — parse for real failures,
  never flag the envelope itself as a problem. When the JSON encoder can't serialize a
  warning shape, plain `mix dialyzer` (MIX_ENV=dev) is authoritative.
- **`mix reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`).
  Smell findings must be fixed, never added to an ignore list. The surface is currently
  clean. Note `Reach.Smell.Checks.UnsafeAtom` accepts `String.to_atom/1` only when its
  argument is a **binary literal** — moving such a call into a macro does not satisfy it,
  so "intern it at compile time" is never a valid remedy here.
- **`deps.audit.gated`** runs `bin/advisory-freshness.sh` (in `onchain-stack`) before
  `mix deps.audit` — `mix_audit` discards its own sync exit status, so a frozen advisory DB
  would otherwise still report green. This repo carries no `.mix_audit_ignore` (audit is clean).

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
| `Descripex` | Main macro module (`use Descripex`, `api/2`, `api/3`, `emit_api/3`) |
| `Descripex.Manifest` | Introspects modules via `Code.fetch_docs/1` to build JSON-serializable API manifests |
| `Descripex.Describe` | Progressive disclosure — `describe/1-3` for library overview, module functions, and function detail |
| `Descripex.MCP` | Converts annotated modules into MCP tool definitions — `tools/1` returns `[%{name, description, inputSchema}]` |
| `Descripex.Discoverable` | Convenience macro — `use Descripex.Discoverable, modules: [...]` generates `describe/0-2` |
| `Mix.Tasks.Descripex.Manifest` | Mix task — `mix descripex.manifest` exports `Manifest.build/1` as JSON to disk |

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

### `emit_api/3` — Variable-Opts Declarations

`api/3` runs `preprocess_schemas/1` on the `opts` AST at macro-expansion time, which calls `Keyword.get/3` (an `is_list` guard) on it — so `api/3` only works when `opts` is a **literal** keyword-list AST. Callers building `opts` inside a `for`-comprehension or any macro-time variable (where the AST is a `{:var, _, _}` node) cannot use `api/3`.

`emit_api/3` is the public escape hatch: same `@doc` / `@doc hints:` / `@descripex_api_declarations` emissions as `api/3`, but it **skips** schema preprocessing, so it accepts a variable `opts`. Compile-time validation in `__before_compile__` still fires for `emit_api/3` declarations (they accumulate into the same attribute). Because preprocessing is skipped, the caller must pre-convert any `schema:` keys; for-comprehension callers typically declare none. To prevent the footgun where a literal `schema: float()` would land raw in `hints`, `emit_api/3` raises `ArgumentError` on a literal keyword-list `opts`, steering such callers back to `api/3`.

### Spec-Derived Param Schemas (typeless fallback)

A `kind: :value` param that declares **no** explicit `schema:` would otherwise be advertised to MCP clients as a typeless (description-only) property — clients then guess at serialization. To close this, `Descripex.enrich_with_specs/2` (called inside `__api__/0`) fills `hints.params.<name>.schema` from the function's own `@spec`: it maps each positional param (via `param_order`) to the matching `@spec` argument type, runs it through `JSONSpec.convert/1`, and merges the result. So `Descripex.MCP.build_property/1` emits a concrete `type`/`enum` for any param whose `@spec` arg is expressible in JSON Schema, without the author repeating the type as a `schema:`.

Caveats: this runs at runtime (cold path — MCP tool-list assembly), not compile time. `Code.Typespec.spec_to_quoted/2` resolves remote types to bare module atoms, so `normalize_remote_aliases/1` rewrites `String.t()` back to the alias form json_spec expects (json_spec supports exactly that one remote type). Types json_spec can't express (`term()`/`any()` → `{}`, other remote types, tuples like `{module, opts}`) are skipped, leaving the param unschema'd rather than emitting a guessed shape. Explicit `schema:` always wins — spec-fill only touches params lacking one.

The `opts:` section gets the same treatment via `fill_opt_schemas_from_type/1`, but the type *source* differs: opts live inside the function's final keyword argument, so `@spec` carries no per-opt type. Instead the opt's declared `type:` atom (`:integer`, `:atom`, `:boolean`, …) is mapped to a type AST and run through the same `JSONSpec.convert`/`safe_convert` path. Atoms json_spec can't express bare (`:list`, `:list_or_map`, `:tuple`) are skipped; explicit `schema:` still wins.

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

- **Single dep**: `json_spec` (compile-time only, zero transitive deps)
- **Pure library**: No GenServers, no state, no side effects
- **Generic**: Zero domain-specific logic — works for any Elixir project
- **Compile-time validation**: Catches param name mismatches and missing functions before runtime
- **Documentation gate**: `.doctor.exs` enforces 100% `@doc`, `@spec`, and `@moduledoc` coverage

## Release Checklist

Before publishing a new version (`mix hex.publish` / version bump in `mix.exs`), sync the external references that drift otherwise:

- `~/.claude/includes/elixir-setup.md` — update the `{:descripex, "~> X.Y"}` dep pin.
- `~/.claude/includes/agent-economy.md` — verify the `api()` / `describe` / `MCP.tools` / `Manifest.build` surface and the `CONSUMING.md` filename references still match.
- Repo `CONSUMING.md` — update the consumer-facing contract for any new/changed API.

Both global includes auto-sync to their marketplace skills, so editing the include is enough — no separate skill edit needed.

## Git Commit Configuration

### Commit Message Format

**Format**: conventional-commits

#### Template
```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore
