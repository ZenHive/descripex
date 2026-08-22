defmodule Descripex.Test.AnnotatedFixture do
  @moduledoc "A test fixture module."
  use Descripex, namespace: "/fixture"

  api(:add, "Add two numbers.",
    params: [
      a: [kind: :value, description: "First number"],
      b: [kind: :value, description: "Second number"]
    ],
    returns: %{type: :number, description: "Sum of a and b"},
    returns_example: 42
  )

  @spec add(number(), number()) :: number()
  def add(a, b), do: a + b

  api(:greet, "Greet someone.",
    params: [
      name: [kind: :value, description: "Name to greet"],
      prefix: [kind: :value, default: "Hello", description: "Greeting prefix"]
    ],
    composes_with: [:add]
  )

  @spec greet(String.t(), String.t()) :: String.t()
  def greet(name, prefix \\ "Hello"), do: "#{prefix}, #{name}!"
end

defmodule Descripex.Test.PlainFixture do
  @moduledoc "A plain module with no Descripex annotations."

  @doc "Multiply two numbers."
  @spec multiply(number(), number()) :: number()
  def multiply(a, b), do: a * b

  @doc false
  def hidden_func, do: :hidden
end

defmodule Descripex.Test.V1.Funding do
  @moduledoc "V1 Funding module."
  use Descripex, namespace: "/v1/funding"

  api(:rate, "Get funding rate.",
    params: [symbol: [kind: :value, description: "Trading pair symbol"]],
    returns: %{type: :float, description: "Funding rate"}
  )

  @spec rate(String.t()) :: float()
  def rate(_symbol), do: 0.01
end

defmodule Descripex.Test.V2.Funding do
  @moduledoc "V2 Funding module."
  use Descripex, namespace: "/v2/funding"

  api(:rate, "Get funding rate v2.",
    params: [symbol: [kind: :value, description: "Trading pair symbol"]],
    returns: %{type: :float, description: "Funding rate v2"}
  )

  @spec rate(String.t()) :: float()
  def rate(_symbol), do: 0.02
end

defmodule Descripex.Test.GammaWalls do
  @moduledoc "Multi-word CamelCase module for short_name regression test."
  use Descripex

  api(:calculate, "Calculate gamma walls.")

  @spec calculate() :: :ok
  def calculate, do: :ok
end

defmodule Descripex.Test.MultiArityFixture do
  @moduledoc "Multi-arity fixture for hints propagation test."
  use Descripex, namespace: "/multi"

  api(:greet, "Say hello.",
    params: [
      name: [kind: :value, description: "Name to greet"],
      opts: [kind: :value, default: [], description: "Options"]
    ],
    returns: %{type: :string, description: "Greeting string"}
  )

  @spec greet(String.t()) :: String.t()
  def greet(name), do: greet(name, [])

  @spec greet(String.t(), keyword()) :: String.t()
  def greet(name, opts), do: "Hello #{name} #{inspect(opts)}"
end

defmodule Descripex.Test.ErrorsFixture do
  @moduledoc "Fixture with mixed error formats for JSON serialization tests."
  use Descripex, namespace: "/errors"

  api(:verify, "Verify a payload.",
    params: [
      payload: [kind: :value, description: "Data to verify"]
    ],
    errors: [
      :timeout,
      {:invalid_payload, "Missing required field"},
      {:verification_failed, "API call failed"}
    ],
    returns: %{type: :boolean, description: "Whether verification passed"}
  )

  @spec verify(map()) :: boolean()
  def verify(_payload), do: true
end

defmodule Descripex.Test.SchemaFixture do
  @moduledoc "Fixture with JSON Schema type annotations for manifest/describe tests."
  use Descripex, namespace: "/schema"

  api(:calculate, "Calculate a result from inputs.",
    params: [
      value: [kind: :value, description: "Input value", schema: float()],
      count: [kind: :value, description: "Repetition count", schema: pos_integer()]
    ],
    opts: [
      mode: [type: :atom, default: :normal, description: "Processing mode", schema: :normal | :fast | :precise]
    ],
    returns: %{type: :float, description: "Calculated result", schema: float()}
  )

  @spec calculate(float(), pos_integer(), keyword()) :: float()
  def calculate(value, count, _opts \\ []), do: value * count
end

defmodule Descripex.Test.NoDocs do
  @moduledoc false
  @spec compute(integer()) :: integer()
  def compute(x), do: x * 2
end

defmodule Descripex.Test.SpecTypedFixture do
  @moduledoc "Fixture whose kind:value params declare no schema: — types come from @spec."
  use Descripex, namespace: "/spec_typed"

  api(:place, "Place an order.",
    params: [
      price: [kind: :value, description: "Limit price"],
      side: [kind: :value, description: "Order side"],
      tags: [kind: :value, default: [], description: "Tags"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec place(float(), :buy | :sell, [String.t()]) :: :ok
  def place(_price, _side, _tags \\ []), do: :ok

  api(:tag, "Tag a record.",
    params: [
      id: [kind: :value, description: "Record id"],
      label: [kind: :value, description: "Atom label"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec tag(integer(), atom()) :: :ok
  def tag(_id, _label), do: :ok

  api(:configure, "Configure a run.",
    params: [id: [kind: :value, description: "Run id"]],
    opts: [
      limit: [type: :integer, default: 10, description: "Max records"],
      mode: [type: :atom, default: :normal, description: "Processing mode"],
      verbose: [type: :boolean, default: false, description: "Verbose logging"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec configure(integer(), keyword()) :: :ok
  def configure(_id, _opts \\ []), do: :ok
end

defmodule Descripex.Test.SpecUnionFixture do
  @moduledoc "Fixture whose @spec params use the list/union forms json_spec rejects wholesale."
  use Descripex, namespace: "/spec_union"

  api(:register, "Register a project.",
    params: [
      warm_paths: [kind: :value, description: "Warm paths"],
      languages: [kind: :value, description: "Languages"],
      tags: [kind: :value, description: "Tags"],
      mode: [kind: :value, description: "Mode"],
      label: [kind: :value, description: "Label"],
      ratio: [kind: :value, description: "Ratio"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec register(
          [String.t()],
          nonempty_list(atom() | String.t()),
          [String.t(), ...],
          atom() | String.t(),
          String.t() | nil,
          integer() | String.t()
        ) :: :ok
  def register(_warm_paths, _languages, _tags, _mode, _label, _ratio), do: :ok

  api(:store, "Store a value.",
    params: [
      key: [kind: :value, description: "Key"],
      handle: [kind: :value, description: "Opaque handle"],
      anything: [kind: :value, description: "Anything at all"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec store(String.t(), {module(), keyword()}, term()) :: :ok
  def store(_key, _handle, _anything), do: :ok

  api(:load, "Load modules.",
    params: [
      modules: [kind: :value, description: "Modules"],
      target: [kind: :value, description: "Target node or module"],
      origin: [kind: :value, description: "Origin"]
    ],
    returns: %{type: :atom, description: "Outcome"}
  )

  @spec load([module()], node(), module() | String.t()) :: :ok
  def load(_modules, _target, _origin), do: :ok

  api(:untyped, "Function with no @spec at all.",
    params: [value: [kind: :value, description: "Value"]],
    returns: %{type: :atom, description: "Outcome"}
  )

  def untyped(_value), do: :ok
end
