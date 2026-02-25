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

  @doc false
  defp contract_literal(doc_text) do
    case Regex.run(
           ~r/```elixir\n# descripex:contract\n(?<contract>[\s\S]*?)\n```/,
           doc_text,
           capture: :all_names
         ) do
      [contract] -> contract
      nil -> flunk("Expected descripex contract block in doc text:\n#{doc_text}")
    end
  end

  @doc false
  defp parse_contract(doc_text) do
    literal = contract_literal(doc_text)
    assert {:ok, ast} = Code.string_to_quoted(literal)
    {contract, _binding} = Code.eval_quoted(ast, [], __ENV__)
    contract
  end

  @doc false
  defp moduledoc_text(docs) do
    {:docs_v1, _, _, _, moduledoc, _, _} = docs

    case moduledoc do
      %{"en" => text} -> text
      :none -> nil
      :hidden -> false
    end
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

    test "escapes curly braces in descriptions to avoid ExDoc IAL warnings" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenBraces do
          use Descripex

          api :parse, "Returns `{:ok, result}` or {:error, reason}.",
            params: [
              data: [kind: :value, description: "Raw data with `{key, value}` pairs and {bare} braces"]
            ],
            returns: %{type: :tuple, description: "{:ok, %{current, history}} or `{:error, :invalid}`"}

          def parse(data), do: {:ok, data}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :parse, 1)

      # Bare braces outside backticks are escaped
      assert doc_text =~ "\\{:error, reason\\}"
      assert doc_text =~ "\\{bare\\}"
      assert doc_text =~ "\\{:ok, %\\{current, history\\}\\}"

      # Braces inside backticks are preserved as-is
      assert doc_text =~ "`{:ok, result}`"
      assert doc_text =~ "`{key, value}`"
      assert doc_text =~ "`{:error, :invalid}`"

      # EarmarkParser produces no warnings on the escaped doc
      assert {:ok, _ast, []} = EarmarkParser.as_ast(doc_text)

      # Hints still contain raw (unescaped) descriptions
      assert metadata.hints.description == "Returns `{:ok, result}` or {:error, reason}."

      assert metadata.hints.params.data.description ==
               "Raw data with `{key, value}` pairs and {bare} braces"

      assert metadata.hints.returns.description ==
               "{:ok, %{current, history}} or `{:error, :invalid}`"
    after
      :code.purge(DocGenBraces)
      :code.delete(DocGenBraces)
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

      assert doc_text =~ "Does nothing."
      assert doc_text =~ "```elixir"
      assert doc_text =~ "# descripex:contract"
      assert parse_contract(doc_text) == %{}
      assert %{hints: %{description: "Does nothing."}} = metadata
    after
      :code.purge(DocGenMinimal)
      :code.delete(DocGenMinimal)
    end

    test "appends parseable contract block after human-readable sections" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenContract do
          use Descripex

          api :price, "Quote a price.",
            params: [
              symbol: [kind: :value, description: "Symbol"],
              orderbook: [kind: :exchange_data, description: "Order book snapshot"]
            ],
            opts: [
              depth: [type: :pos_integer, default: 10, description: "Book depth"]
            ],
            returns: %{type: :tuple, description: "{:ok, %{bid, ask}}"},
            errors: [:timeout, not_found: "Symbol not available"]

          def price(_symbol, _orderbook, _opts \\\\ []), do: {:ok, %{bid: 1.0, ask: 1.1}}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :price, 3)
      contract = parse_contract(doc_text)

      assert doc_text =~ "## Parameters"
      assert doc_text =~ "## Options"
      assert doc_text =~ "## Returns"
      assert doc_text =~ "## Errors"
      assert doc_text =~ "```elixir"
      assert doc_text =~ "# descripex:contract"
      assert {:ok, _ast, []} = EarmarkParser.as_ast(doc_text)

      {errors_pos, _} = :binary.match(doc_text, "## Errors")
      {contract_pos, _} = :binary.match(doc_text, "# descripex:contract")
      assert contract_pos > errors_pos

      refute Map.has_key?(contract, :description)
      assert contract.params.symbol.kind == :value
      assert contract.params.orderbook.kind == :exchange_data
      assert contract.opts.depth.type == :pos_integer
      assert contract.returns.type == :tuple
      assert contract.errors == [:timeout, not_found: "Symbol not available"]

      assert metadata.hints.description == "Quote a price."
    after
      :code.purge(DocGenContract)
      :code.delete(DocGenContract)
    end

    test "renders returns_example in doc text, hints, and contract" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenReturnsExample do
          use Descripex

          api :quote, "Quote funding rate.",
            returns: %{type: :tuple, description: "{:ok, %{rate: float()}}"},
            returns_example: {:ok, %{rate: 10.95}}

          def quote, do: {:ok, %{rate: 10.95}}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :quote, 0)
      contract = parse_contract(doc_text)

      assert doc_text =~ "## Returns"
      assert doc_text =~ "\\{:ok, %\\{rate: float()\\}\\} (`tuple`)"
      assert doc_text =~ "### Example"
      assert doc_text =~ "```elixir\n{:ok, %{rate: 10.95}}\n```"
      assert {:ok, _ast, []} = EarmarkParser.as_ast(doc_text)

      assert metadata.hints.returns_example == {:ok, %{rate: 10.95}}
      assert contract.returns_example == {:ok, %{rate: 10.95}}
    after
      :code.purge(DocGenReturnsExample)
      :code.delete(DocGenReturnsExample)
    end

    test "renders returns section when only returns_example is provided" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenReturnsExampleOnly do
          use Descripex

          api :fetch, "Fetch data.",
            returns_example: {:error, :timeout}

          def fetch, do: {:error, :timeout}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :fetch, 0)
      contract = parse_contract(doc_text)

      assert doc_text =~ "## Returns"
      assert doc_text =~ "### Example"
      assert doc_text =~ "```elixir\n{:error, :timeout}\n```"
      assert metadata.hints.returns_example == {:error, :timeout}
      assert contract.returns_example == {:error, :timeout}
    after
      :code.purge(DocGenReturnsExampleOnly)
      :code.delete(DocGenReturnsExampleOnly)
    end

    test "does not render returns example when returns_example is absent" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenNoReturnsExample do
          use Descripex

          api :sum, "Add numbers.",
            returns: %{type: :integer, description: "Sum result"}

          def sum, do: 3
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :sum, 0)
      contract = parse_contract(doc_text)

      assert doc_text =~ "## Returns"
      refute doc_text =~ "### Example"
      refute Map.has_key?(metadata.hints, :returns_example)
      refute Map.has_key?(contract, :returns_example)
    after
      :code.purge(DocGenNoReturnsExample)
      :code.delete(DocGenNoReturnsExample)
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

  describe "moduledoc API Functions table generation" do
    test "appends API Functions table to existing moduledoc text" do
      docs =
        compile_and_fetch_docs("""
        defmodule ModuledocTableAppend do
          @moduledoc "Public API for quote helpers."
          use Descripex

          api :quote, "Returns a quote.",
            params: [
              symbol: [kind: :value, description: "Asset symbol"],
              snapshot: [kind: :exchange_data, description: "Orderbook snapshot"]
            ]

          api :ping, "Health check."

          def quote(_symbol, _snapshot), do: {:ok, 1.0}
          def ping, do: :pong
        end
        """)

      text = moduledoc_text(docs)

      assert text =~ "Public API for quote helpers."
      assert text =~ "## API Functions"
      assert text =~ "| Function | Arity | Description | Param Kinds |"
      assert text =~ "| `quote` | 2 | Returns a quote. | `symbol: value`, `snapshot: exchange_data` |"
      assert text =~ "| `ping` | 0 | Health check. | - |"
    after
      :code.purge(ModuledocTableAppend)
      :code.delete(ModuledocTableAppend)
    end

    test "preserves namespace metadata when appending API Functions table" do
      docs =
        compile_and_fetch_docs("""
        defmodule ModuledocNamespacePreserved do
          @moduledoc "Namespaced module."
          use Descripex, namespace: "/testing"

          api :ping, "Ping."
          def ping, do: :pong
        end
        """)

      {:docs_v1, _, _, _, _, moduledoc_meta, _} = docs
      text = moduledoc_text(docs)

      assert moduledoc_meta[:namespace] == "/testing"
      assert text =~ "Namespaced module."
      assert text =~ "## API Functions"
      assert text =~ "| `ping` | 0 | Ping. | - |"
    after
      :code.purge(ModuledocNamespacePreserved)
      :code.delete(ModuledocNamespacePreserved)
    end

    test "leaves @moduledoc false unchanged" do
      docs =
        compile_and_fetch_docs("""
        defmodule ModuledocHiddenPreserved do
          @moduledoc false
          use Descripex

          api :ping, "Ping."
          def ping, do: :pong
        end
        """)

      assert moduledoc_text(docs) == false
    after
      :code.purge(ModuledocHiddenPreserved)
      :code.delete(ModuledocHiddenPreserved)
    end

    test "generates table when moduledoc is nil" do
      docs =
        compile_and_fetch_docs("""
        defmodule ModuledocNilGetsTable do
          @moduledoc nil
          use Descripex

          api :ping, "Ping."
          def ping, do: :pong
        end
        """)

      text = moduledoc_text(docs)

      assert is_binary(text)
      assert text =~ "## API Functions"
      assert text =~ "| `ping` | 0 | Ping. | - |"
    after
      :code.purge(ModuledocNilGetsTable)
      :code.delete(ModuledocNilGetsTable)
    end
  end

  describe "errors metadata" do
    test "atom errors render in doc and are included in hints" do
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

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :divide, 2)

      assert doc_text =~ "## Errors"
      assert doc_text =~ "  * `:division_by_zero`"
      assert {:ok, _ast, []} = EarmarkParser.as_ast(doc_text)
      assert %{hints: hints} = metadata
      assert hints.errors == [:division_by_zero]
    after
      :code.purge(DocGenErrors)
      :code.delete(DocGenErrors)
    end

    test "no errors section is rendered when errors are not declared" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenNoErrors do
          use Descripex

          api :ping, "Ping."

          def ping, do: :pong
        end
        """)

      {_, _, _, %{"en" => doc_text}, _metadata} = find_func_doc(docs, :ping, 0)

      refute doc_text =~ "## Errors"
    after
      :code.purge(DocGenNoErrors)
      :code.delete(DocGenNoErrors)
    end

    test "keyword errors render descriptions in doc and keep keyword hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenKeywordErrors do
          use Descripex

          api :find, "Find record.",
            errors: [not_found: "Record does not exist"]

          def find(_id), do: {:error, :not_found}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :find, 1)

      assert doc_text =~ "## Errors"
      assert doc_text =~ "  * `:not_found` - Record does not exist"
      assert %{hints: hints} = metadata
      assert hints.errors == [not_found: "Record does not exist"]
    after
      :code.purge(DocGenKeywordErrors)
      :code.delete(DocGenKeywordErrors)
    end

    test "mixed atom and keyword errors render in order and preserve hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenMixedErrors do
          use Descripex

          api :fetch, "Fetch record.",
            errors: [:timeout, not_found: "Record does not exist"]

          def fetch(_id), do: {:error, :timeout}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :fetch, 1)

      assert doc_text =~ "## Errors"
      assert doc_text =~ "  * `:timeout`"
      assert doc_text =~ "  * `:not_found` - Record does not exist"
      assert doc_text =~ ~r/  \* `:timeout`\n  \* `:not_found` - Record does not exist/
      assert %{hints: hints} = metadata
      assert hints.errors == [:timeout, not_found: "Record does not exist"]
    after
      :code.purge(DocGenMixedErrors)
      :code.delete(DocGenMixedErrors)
    end

    test "keyword error descriptions with braces are escaped and hints stay raw" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenErrorBraces do
          use Descripex

          api :parse, "Parse input.",
            errors: [parse_error: "Returns {:error, reason}"]

          def parse(_input), do: {:error, :parse_error}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :parse, 1)

      assert doc_text =~ "  * `:parse_error` - Returns \\{:error, reason\\}"
      assert {:ok, _ast, []} = EarmarkParser.as_ast(doc_text)
      assert metadata.hints.errors == [parse_error: "Returns {:error, reason}"]
    after
      :code.purge(DocGenErrorBraces)
      :code.delete(DocGenErrorBraces)
    end
  end
end
