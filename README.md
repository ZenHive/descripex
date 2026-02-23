# Descripex

Self-describing API declarations for Elixir. Define a function's documentation, machine-readable hints metadata, and runtime introspection with a single `api()` macro call — no separate `@doc` blocks needed.

## Installation

Add `descripex` to your dependencies (ZenHive org package):

```elixir
def deps do
  [
    {:descripex, "~> 0.1"}
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
    returns: %{type: :float, description: "Annualized percentage rate"}
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

## Compile-Time Validation

Descripex validates declarations at compile time:

- Every `api(:name, ...)` must have a matching `def name(...)`
- Declared param names must match actual function argument names by position
- Mismatches raise `CompileError` before your code ever runs

## Manifest

Build a JSON-serializable manifest from all declared modules:

```elixir
Descripex.Manifest.build([MyLib.Funding, MyLib.Risk])
```

## Documentation

Full documentation is available on [HexDocs](https://hex.pm/packages/descripex).

## License

MIT
