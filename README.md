# Descripex

Self-describing API declarations for Elixir. Define a function's documentation, machine-readable hints metadata, and runtime introspection with a single `api()` macro call — no separate `@doc` blocks needed.

## Installation

Add `descripex` to your dependencies:

```elixir
def deps do
  [
    {:descripex, "~> 0.6"}
  ]
end
```

## Usage

```elixir
defmodule MyLib.Funding do
  use Descripex, namespace: "/funding"

  api(:annualize, "Annualize a per-period funding rate to APR.",
    params: [
      rate: [kind: :value, description: "Per-period funding rate as decimal", schema: float()],
      period_hours: [kind: :value, default: 8, description: "Hours per period", schema: pos_integer()]
    ],
    returns: %{type: :float, description: "Annualized percentage rate", schema: float()},
    returns_example: {:ok, %{apr: 10.95}}
  )

  @spec annualize(number(), pos_integer()) :: float()
  def annualize(rate, period_hours \\ 8) do
    rate * (365 * 24 / period_hours) * 100
  end
end
```

The `api` macro generates:

- **`@doc`** — human-readable documentation from the description and params
- **`@doc hints:`** — machine-readable metadata for agent consumption
- **`__api__/0`** and **`__api__/1`** — runtime introspection functions
- **`schema:`** — Elixir type syntax compiled to JSON Schema via [json_spec](https://hexdocs.pm/json_spec) at compile time (zero runtime cost)

### `api/3` option highlights

- `returns` defines return shape and human summary
- `returns_example` adds a concrete example rendered in docs and included in `@doc hints:`
- `schema` on params/opts/returns compiles Elixir type syntax (e.g., `float()`, `[String.t()]`, `:buy | :sell`) to JSON Schema at compile time
- `composes_with` declares intra-module composition relationships (e.g., `[:normalize, :persist]`)

## Manual @doc Coexistence

`api()` writes to two independent slots in the BEAM docs chunk: doc text (slot 4) and hints metadata (slot 5). You can write a manual `@doc` **after** `api()` to provide custom prose while keeping the structured metadata:

```elixir
api(:imbalance!, "Calculate orderbook imbalance (raises on error).",
  params: [orderbook: [kind: :exchange_data, description: "Orderbook data"]],
  returns: %{type: :float, description: "Imbalance ratio"}
)

@doc "Bang variant of `imbalance/2`. Returns the float directly or raises on error."
def imbalance!(orderbook, depth \\ 10), do: ...
```

The function gets both the custom `@doc` text and the full machine-readable `hints` contract.

## Compile-Time Validation

Descripex validates declarations at compile time:

- Every `api(:name, ...)` must have a matching `def name(...)`
- Declared param names must match actual function argument names by position
- Mismatches raise `CompileError` before your code ever runs

## ExDoc Compatibility

Descripex automatically escapes `{` and `}` in description strings when generating `@doc` text. This prevents ExDoc's Earmark parser from misinterpreting Elixir-style return types (e.g., `{:ok, %{current, history}}`) as [Inline Attribute Lists](https://hexdocs.pm/earmark_parser/EarmarkParser.html).

The raw (unescaped) descriptions are preserved in `@doc hints:` metadata — only the human-readable `@doc` text is escaped.

## Progressive Disclosure

Discover a library's API incrementally — from overview to function detail:

```elixir
# Make your library discoverable
defmodule MyLib do
  use Descripex.Discoverable, modules: [MyLib.Funding, MyLib.Risk]
end

MyLib.describe()                     # Level 1: library overview
MyLib.describe(:funding)             # Level 2: module functions
MyLib.describe(:funding, :annualize) # Level 3: function detail
```

Short names are derived from the last module segment (e.g., `MyLib.Funding` → `:funding`). Full module atoms also work. Non-Descripex modules are included with basic function listings.

Or use the functional API directly:

```elixir
modules = [MyLib.Funding, MyLib.Risk]
Descripex.Describe.describe(modules)
Descripex.Describe.describe(modules, :funding, :annualize)
```

## Manifest

Build a JSON-serializable manifest from all declared modules:

```elixir
Descripex.Manifest.build([MyLib.Funding, MyLib.Risk])
```

## JSON Schema

Add `schema:` to params, opts, or returns to compile Elixir type syntax into JSON Schema at compile time:

```elixir
params: [
  side: [kind: :value, description: "Trade side", schema: :buy | :sell],
  prices: [kind: :value, description: "Price list", schema: [float()]]
],
returns: %{type: :map, description: "Result", schema: %{score: float(), tags: [String.t()]}}
```

Conversion is handled by [json_spec](https://hexdocs.pm/json_spec) at compile time; the resulting JSON Schema map lands in `hints.params.*.schema` and `hints.returns.schema`. Params without `schema:` are unaffected.

## MCP Tool Generation

Convert annotated modules into [MCP](https://modelcontextprotocol.io) tool definitions:

```elixir
Descripex.MCP.tools([MyLib.Funding, MyLib.Risk])
# => [%{name: "funding__annualize", description: "...", inputSchema: %{...}}, ...]
```

Each `api()`-annotated function becomes a tool with `name`, `description`, and `inputSchema`. Params with `schema:` get typed JSON Schema properties; params without get description-only properties. Pass `name_style: :full` for fully-qualified tool names.

## Static JSON Export

Export the manifest as JSON to disk:

```bash
mix descripex.manifest MyApp.Funding MyApp.Risk
mix descripex.manifest --app my_app           # auto-discover annotated modules
mix descripex.manifest --pretty --output priv/manifest.json MyApp.Funding
```

Requires `jason ~> 1.4` as a dev dependency in your project. Modules can also be configured via `config :descripex, manifest_modules: [...]`.

## Dogfooding

Descripex describes itself. The library's own modules use `api()` declarations and `Discoverable`:

```elixir
Descripex.describe()                     # Overview of Manifest, Describe, and MCP
Descripex.describe(:mcp)                 # Functions in MCP
Descripex.describe(:mcp, :tools)         # Full detail for tools/1
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/descripex).

## Quality Gates

Run `mix doctor` as part of local/CI checks. This project enforces 100% `@doc`, `@spec`, and `@moduledoc` coverage.

## License

MIT
