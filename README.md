# Descripex

Self-describing API declarations for Elixir. Define a function's documentation, machine-readable hints metadata, and runtime introspection with a single `api()` macro call — no separate `@doc` blocks needed.

## Installation

Add `descripex` to your dependencies:

```elixir
def deps do
  [
    {:descripex, "~> 0.5"}
  ]
end
```

## Usage

```elixir
defmodule MyLib.Funding do
  use Descripex, namespace: "/funding"

  api(:annualize, "Annualize a per-period funding rate to APR.",
    params: [
      rate: [kind: :value, description: "Per-period funding rate as decimal"],
      period_hours: [kind: :value, default: 8, description: "Hours per period"]
    ],
    returns: %{type: :float, description: "Annualized percentage rate"},
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

### `api/3` option highlights

- `returns` defines return shape and human summary
- `returns_example` adds a concrete example rendered in docs and included in `@doc hints:`
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

## Dogfooding

Descripex describes itself. The library's own modules use `api()` declarations and `Discoverable`:

```elixir
Descripex.describe()                     # Overview of Manifest and Describe
Descripex.describe(:manifest)            # Functions in Manifest
Descripex.describe(:manifest, :build)    # Full detail for build/1
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/descripex).

## Quality Gates

Run `mix doctor` as part of local/CI checks. This project enforces 100% `@doc`, `@spec`, and `@moduledoc` coverage.

## License

MIT
