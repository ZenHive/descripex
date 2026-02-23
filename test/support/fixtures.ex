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

  @spec multiply(number(), number()) :: number()
  def multiply(a, b), do: a * b
end
