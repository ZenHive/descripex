defmodule Descripex.Discoverable do
  @moduledoc """
  Convenience macro that generates `describe/0-2` functions closing over a module list.

  ## Usage

      defmodule MyLib do
        use Descripex.Discoverable, modules: [MyLib.Funding, MyLib.Risk]
      end

      MyLib.describe()                      # Level 1: library overview
      MyLib.describe("funding")             # Level 2: module functions
      MyLib.describe("funding", :annualize) # Level 3: function detail
      MyLib.__descripex_modules__()        # => [MyLib.Funding, MyLib.Risk]

  """

  @doc false
  defmacro __using__(opts) do
    modules = Keyword.get(opts, :modules)

    if !modules do
      raise CompileError,
        description: "use Descripex.Discoverable requires a :modules option (list of module atoms)"
    end

    quote do
      @doc "Return a Level 1 overview of all modules in this library."
      @spec describe() :: [map()]
      def describe, do: Descripex.Describe.describe(unquote(modules))

      @doc "Return Level 2 function list for a module (by full atom, or short name as string or atom)."
      @spec describe(module() | atom() | String.t()) :: [map()]
      def describe(mod_or_short), do: Descripex.Describe.describe(unquote(modules), mod_or_short)

      @doc "Return Level 3 function detail (or `nil` if not found)."
      @spec describe(module() | atom() | String.t(), atom()) :: map() | nil
      def describe(mod_or_short, func_name), do: Descripex.Describe.describe(unquote(modules), mod_or_short, func_name)

      @doc "Return the list of modules registered with this library."
      @spec __descripex_modules__() :: [module()]
      def __descripex_modules__, do: unquote(modules)
    end
  end
end
