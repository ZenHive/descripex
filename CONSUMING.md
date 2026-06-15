# Consuming Descripex Libraries

A guide for AI agents and developers who want to **discover and call** the API of a
descripex-powered Elixir library — without reading source or parsing docs.

## Why Descripex Libraries Are Worth Finding

Most Elixir libraries require you to read source code, parse docs, and guess at return shapes. A descripex-powered library **tells you its entire API contract in structured data** — params, types, defaults, errors, return shapes, composition hints — through three function calls.

No doc parsing. No source diving. No guessing.

```elixir
MyLib.describe()                     # what modules exist?
MyLib.describe(:funding)             # what functions does it have?
MyLib.describe(:funding, :annualize) # tell me everything about this function
```

Every contract is **compile-time validated** — if the library compiles, the metadata aligns with actual function signatures and arities. You can trust the structure and focus your effort on behavior.

## Detecting Descripex Support

A library uses descripex if any of these are true:
- `function_exported?(SomeModule, :__api__, 0)` — module-level introspection
- `function_exported?(MyLib, :describe, 0)` — library-level discovery
- A module's `@moduledoc` contains an "API Functions" table

**When you detect it, use it.** The structured metadata is always more reliable than parsing `@doc` strings.

## Discovery Workflow

Three levels, each one step deeper. Start broad, drill into what you need.

### Level 1: What Modules Exist?

```elixir
MyLib.describe()
```

```elixir
[%{
  module: MyLib.Funding,       # full module atom
  short_name: :funding,        # use this for Level 2/3 — shorter, friendlier
  namespace: "/funding",       # URL grouping hint (or nil)
  description: "...",          # @moduledoc text (or nil)
  function_count: 3,           # how many public API functions
  annotated?: true             # true = full contracts available
}]
```

`annotated?: true` means full contracts (params, returns, errors). `false` means only basic `@doc`/`@spec` info — still useful, just less structured.

### Level 2: What Functions Does It Have?

```elixir
MyLib.describe(:funding)
```

```elixir
[%{
  name: :annualize,            # function name (atom)
  arity: 2,                    # max arity
  defaults: 1,                 # number of optional args — callable with 1 or 2 args
  description: "...",          # one-line description
  spec: "annualize(...) :: float()"  # typespec string (or nil)
}]
```

Scan this to find the function you need. Then drill in.

### Level 3: Full Function Contract

```elixir
MyLib.describe(:funding, :annualize)
```

This is where it pays off — everything you need to call the function correctly:

```elixir
%{
  name: :annualize,
  arity: 2,
  defaults: 1,
  description: "Annualize a per-period funding rate to APR.",
  spec: "annualize(number(), pos_integer()) :: float()",
  params: %{
    rate: %{kind: :value, description: "Per-period funding rate as decimal",
            schema: %{"type" => "number"}},        # JSON Schema, derived from @spec
    period_hours: %{kind: :value, default: 8, description: "Hours per period",
                    schema: %{"type" => "integer"}}
  },
  opts: %{                     # keyword options (or nil if none)
    precision: %{type: :integer, default: 2, description: "Decimal places",
                 schema: %{"type" => "integer"}}   # derived from the opt's type:
  },
  returns: %{type: :float, description: "Annualized percentage rate"},
  returns_example: 10.95,      # a concrete value you can expect back
  errors: [invalid_period: "Period must be > 0"],
  composes_with: [:normalize_rate]  # what to call next
}
```

You now know the param order, which are optional, what types to pass, what comes back, what can go wrong, and what to chain with. **You can call this function correctly without reading a single line of source code.**

### Reading the Contract

**`params`** — Positional arguments. Pass them in order. Check `kind`:
- `:value` — you provide this directly (a number, string, config)
- `:exchange_data` — must be fetched from an external source first (the param may include a `source` hint telling you where to get it)

**`opts`** — Keyword options. Pass as last argument: `annualize(rate, period, precision: 4)`.

**`schema`** — A JSON Schema map present on most params/opts, giving the wire type for JSON/MCP callers. Derived automatically from the function's `@spec` (params) or the opt's `type:` (opts), or from an explicit `schema:` declaration. Absent only for types a typespec can't express (e.g. `term()`, tuples). Elixir callers can ignore it and use `kind`/`type`/`default`.

**`defaults`** — Number of trailing params with defaults. If `arity: 3, defaults: 1`, you can call with 2 or 3 args.

**`errors`** — Known error cases the function may return or raise; treat these as contract hints and follow the library's actual return conventions.

**`composes_with`** — Other functions in the same module that chain well with this one. Follow the chain to build pipelines without guessing.

**`returns_example`** — A concrete value showing what the output looks like. Use this to understand the shape before you call.

## Combining Manual @doc with api()

`api()` generates both human-readable `@doc` text and machine-readable `@doc hints:` metadata. These live in **separate slots** in Elixir's compiled BEAM docs (element 4 and element 5 of the docs tuple) — they never collide.

This means you can write a manual `@doc` **after** `api()` to provide custom prose while keeping the structured metadata:

```elixir
# api() writes hints metadata (slot 5) AND generated @doc text (slot 4)
api(:imbalance!, "Calculate orderbook bid/ask imbalance (raises on error).",
  params: [
    orderbook: [kind: :exchange_data, description: "Orderbook data"],
    depth: [kind: :value, default: 10, description: "Depth levels"]
  ],
  returns: %{type: :float, description: "Imbalance ratio"}
)

# Manual @doc AFTER api() — overwrites only slot 4 (prose), hints in slot 5 survive
@doc "Bang variant of `imbalance/2`. Returns the float directly or raises on error."
@spec imbalance!(map(), pos_integer()) :: float()
def imbalance!(orderbook, depth \\ 10), do: ...
```

Result: the function gets **both** the rich human-friendly `@doc` text AND the full machine-readable `hints` contract. Best of both worlds.

**Important:** The manual `@doc` must come **after** `api()` — Elixir uses last-wins for `@doc` text. If placed before, `api()`'s generated text overwrites it.

## Alternative Entry Points

### Direct Module Introspection

When you know the exact module, skip the top-level and go direct:

```elixir
MyLib.Funding.__api__()
# => [%{name: :annualize, arity: 2, defaults: 1, spec: "...", hints: %{...}}, ...]

MyLib.Funding.__api__(:annualize)
# => %{name: :annualize, arity: 2, defaults: 1, spec: "...", hints: %{...}}
```

The `hints` map has the same fields as Level 3 (`params`, `opts`, `returns`, `returns_example`, `errors`, `composes_with`, `description`).

**`__api__/0` is runtime-enriched; the BEAM doc chunk is not.** `__api__/0` fills
`hints.params.<name>.schema` / `hints.opts.<name>.schema` from the function's `@spec` and
declared `type:` at runtime. The compile-time doc chunk (`Code.fetch_docs/1` → `meta[:hints]`)
is the raw declared surface and carries no spec-derived schemas, so the two diverge on
`:schema`. This is intentional. If you cross-check the two surfaces for equality (e.g. to
detect `api()` misattachment), normalize **both** with `Descripex.normalize_for_doc_compare/1`
first — it strips every `:schema` key so the comparison doesn't false-positive on the
injected schema:

```elixir
Descripex.normalize_for_doc_compare(MyLib.Funding.__api__(:annualize).hints) ==
  Descripex.normalize_for_doc_compare(meta_hints)
```

### Get the Module List

```elixir
MyLib.__descripex_modules__()
# => [MyLib.Funding, MyLib.Risk]
```

### Without a Top-Level Discoverable

Use `Descripex.Describe` directly — same three levels, but you pass the module list:

```elixir
Descripex.Describe.describe([MyLib.Funding, MyLib.Risk])
Descripex.Describe.describe([MyLib.Funding, MyLib.Risk], :funding)
Descripex.Describe.describe([MyLib.Funding, MyLib.Risk], :funding, :annualize)
```

### Manifest (Batch/Offline)

Grab the entire library's API as a JSON-serializable map:

```elixir
Descripex.Manifest.build([MyLib.Funding, MyLib.Risk])
```

```elixir
%{
  version: "1.0",
  generated_at: "2025-01-01T00:00:00Z",
  modules: [%{
    module: "MyLib.Funding",     # strings in manifest (JSON-friendly)
    namespace: "/funding",
    description: "...",
    functions: [%{
      name: "annualize",        # strings (not atoms)
      arity: 2,
      defaults: 1,
      signature: "annualize(rate, period_hours)",
      description: "...",
      spec: "annualize(number(), pos_integer()) :: float()",
      hints: %{...}             # same shape as __api__ hints
    }]
  }]
}
```

Note: Manifest uses **strings** for module/function names. `__api__` and `describe` use **atoms**.

For an **offline / batch** export to a file (CI, agent toolchains), use the Mix task instead of
calling `Manifest.build/1` yourself:

```bash
mix descripex.manifest MyLib.Funding MyLib.Risk   # writes api_manifest.json
mix descripex.manifest --app my_app               # auto-discover annotated modules in an app
mix descripex.manifest --pretty -o tools.json MyLib.Funding
```

### MCP Tool Definitions

If you host the library behind the Model Context Protocol, turn its annotated modules straight
into MCP tool definitions — no hand-written schemas:

```elixir
Descripex.MCP.tools([MyLib.Funding, MyLib.Risk])
# => [%{
#   name: "funding__annualize",          # "<short_module>__<function>"
#   description: "Annualize a per-period funding rate to APR.",
#   inputSchema: %{type: "object", properties: %{...}, required: [...]}
# }, ...]
```

`inputSchema` is a JSON Schema assembled from the function's `params` and `opts` (the same
schemas you see at Level 3). Pass `name_style: :full` for fully-qualified tool names
(`my_lib_funding__annualize`). Functions without `api()` annotations are skipped.

## Quick Reference

| Want to... | Call |
|------------|------|
| List all modules | `MyLib.describe()` |
| List functions in a module | `MyLib.describe(:funding)` |
| Get full function contract | `MyLib.describe(:funding, :annualize)` |
| Get module list | `MyLib.__descripex_modules__()` |
| Introspect one module directly | `MyLib.Funding.__api__()` |
| Introspect one function directly | `MyLib.Funding.__api__(:annualize)` |
| Get everything as JSON-ready map | `Descripex.Manifest.build(modules)` |
| Export manifest to disk | `mix descripex.manifest MyLib.Funding` |
| Get MCP tool definitions | `Descripex.MCP.tools(modules)` |
| Detect descripex support | `function_exported?(Mod, :__api__, 0)` |
