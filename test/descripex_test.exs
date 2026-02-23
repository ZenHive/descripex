defmodule DescripexTest do
  use ExUnit.Case, async: true

  # Test env has docs: false. Temporarily enable docs, compile, extract Docs chunk.
  @doc false
  defp compile_and_fetch_docs(code) do
    prev = Code.compiler_options(docs: true)

    try do
      [{_module, binary}] = Code.compile_string(code)
      {:ok, {_, [{~c"Docs", docs_bin}]}} = :beam_lib.chunks(binary, [~c"Docs"])
      :erlang.binary_to_term(docs_bin)
    after
      Code.compiler_options(docs: prev[:docs])
    end
  end

  @doc false
  defp find_func_doc(docs, name, arity) do
    {:docs_v1, _, _, _, _, _, func_docs} = docs

    Enum.find(func_docs, fn
      {{:function, ^name, ^arity}, _, _, _, _} -> true
      _ -> false
    end)
  end

  describe "doc generation from api macro" do
    test "generates @doc with description and params" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenBasic do
          use Descripex, namespace: "/test"

          api :hello, "Says hello.",
            params: [
              name: [kind: :value, description: "Name to greet"]
            ],
            returns: %{type: :string, description: "Greeting"}

          def hello(name), do: "Hello \#{name}"
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :hello, 1)

      # Doc generated from api() metadata
      assert doc_text =~ "Says hello."
      assert doc_text =~ "## Parameters"
      assert doc_text =~ "`name` - Name to greet"
      assert doc_text =~ "## Returns"
      assert doc_text =~ "Greeting"

      # Hints also present in metadata
      assert %{hints: hints} = metadata
      assert hints.description == "Says hello."
      assert hints.params.name.kind == :value
      assert hints.returns.type == :string
    after
      :code.purge(DocGenBasic)
      :code.delete(DocGenBasic)
    end

    test "generates @doc with opts section" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenOpts do
          use Descripex

          api :search, "Search items.",
            params: [
              items: [kind: :exchange_data, description: "List of items"]
            ],
            opts: [
              threshold: [type: :float, default: 2.0, description: "Threshold"]
            ]

          def search(items, opts \\\\ []) do
            threshold = Keyword.get(opts, :threshold, 2.0)
            Enum.filter(items, & &1 > threshold)
          end
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :search, 2)

      assert doc_text =~ "Search items."
      assert doc_text =~ "## Parameters"
      assert doc_text =~ "`items` - List of items"
      assert doc_text =~ "## Options"
      assert doc_text =~ "`threshold` - Threshold (default: `2.0`)"

      assert %{hints: hints} = metadata
      assert hints.opts.threshold.type == :float
    after
      :code.purge(DocGenOpts)
      :code.delete(DocGenOpts)
    end

    test "description-only api generates minimal doc" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenMinimal do
          use Descripex

          api :noop, "Does nothing."

          def noop, do: :ok
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :noop, 0)

      # Just the description, no sections
      assert doc_text == "Does nothing."
      assert %{hints: %{description: "Does nothing."}} = metadata
    after
      :code.purge(DocGenMinimal)
      :code.delete(DocGenMinimal)
    end
  end

  describe "compile-time validation" do
    test "function with defaults compiles and validates" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidDefaults do
          use Descripex

          api :greet, "Greet with configurable excitement.",
            params: [
              name: [kind: :value, description: "Name"],
              enthusiasm: [kind: :value, default: 1, description: "Exclamation count"]
            ]

          def greet(name, enthusiasm \\\\ 1) do
            "Hello \#{name}" <> String.duplicate("!", enthusiasm)
          end
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :greet, 2)

      assert %{hints: %{params: params}} = metadata
      assert Map.has_key?(params, :name)
      assert Map.has_key?(params, :enthusiasm)
    after
      :code.purge(ValidDefaults)
      :code.delete(ValidDefaults)
    end

    test "multi-clause function validates against clause with named params" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidMultiClause do
          use Descripex

          api :process, "Process a list.",
            params: [
              items: [kind: :value, description: "Items to process"]
            ]

          def process([]), do: []
          def process(items) when is_list(items), do: items
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :process, 1)

      assert %{hints: %{params: %{items: _}}} = metadata
    after
      :code.purge(ValidMultiClause)
      :code.delete(ValidMultiClause)
    end

    test "namespace appears in moduledoc metadata" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidNamespace do
          @moduledoc "Test module."
          use Descripex, namespace: "/testing"

          api :ping, "Ping."
          def ping, do: :pong
        end
        """)

      {:docs_v1, _, _, _, _, moduledoc_meta, _} = docs
      assert moduledoc_meta[:namespace] == "/testing"
    after
      :code.purge(ValidNamespace)
      :code.delete(ValidNamespace)
    end

    test "raises CompileError for missing function" do
      assert_raise CompileError, ~r/api declaration for :missing has no matching def/, fn ->
        Code.compile_string("""
        defmodule InvalidMissing do
          use Descripex

          api :missing, "Missing function.",
            params: [x: [kind: :value, description: "X"]]

          def other_func(x), do: x
        end
        """)
      end
    after
      :code.purge(InvalidMissing)
      :code.delete(InvalidMissing)
    end

    test "raises CompileError for param name mismatch" do
      assert_raise CompileError, ~r/api :add param :x .* doesn't match def param :a/, fn ->
        Code.compile_string("""
        defmodule InvalidParamName do
          use Descripex

          api :add, "Add numbers.",
            params: [
              x: [kind: :value, description: "First"],
              y: [kind: :value, description: "Second"]
            ]

          def add(a, b), do: a + b
        end
        """)
      end
    after
      :code.purge(InvalidParamName)
      :code.delete(InvalidParamName)
    end
  end

  describe "errors metadata" do
    test "errors list is included in hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenErrors do
          use Descripex

          api :divide, "Divide two numbers.",
            params: [
              a: [kind: :value, description: "Numerator"],
              b: [kind: :value, description: "Denominator"]
            ],
            errors: [:division_by_zero],
            returns: %{type: :float, description: "Result"}

          def divide(_a, 0), do: {:error, :division_by_zero}
          def divide(a, b), do: {:ok, a / b}
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :divide, 2)

      assert %{hints: hints} = metadata
      assert hints.errors == [:division_by_zero]
    after
      :code.purge(DocGenErrors)
      :code.delete(DocGenErrors)
    end
  end
end
