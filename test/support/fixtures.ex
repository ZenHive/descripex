defmodule Descripex.Test.AnnotatedFixture do
  @moduledoc "A test fixture module."
  use Descripex, namespace: "/fixture"

  api(:add, "Add two numbers.",
    params: [
      a: [kind: :value, description: "First number"],
      b: [kind: :value, description: "Second number"]
    ],
    returns: %{type: :number, description: "Sum of a and b"}
  )

  @spec add(number(), number()) :: number()
  def add(a, b), do: a + b

  api(:greet, "Greet someone.",
    params: [
      name: [kind: :value, description: "Name to greet"],
      prefix: [kind: :value, default: "Hello", description: "Greeting prefix"]
    ]
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

defmodule Descripex.Test.NoDocs do
  @moduledoc false
  @spec compute(integer()) :: integer()
  def compute(x), do: x * 2
end
