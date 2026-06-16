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

  describe "self-describing library (dogfooding)" do
    test "__descripex_modules__/0 returns annotated modules" do
      assert Descripex.__descripex_modules__() == [Descripex.Manifest, Descripex.Describe, Descripex.MCP]
    end

    test "describe/0 returns Level 1 overview of Manifest and Describe" do
      overview = Descripex.describe()

      assert length(overview) == 3
      modules = Enum.map(overview, & &1.module)
      assert Descripex.Manifest in modules
      assert Descripex.Describe in modules
      assert Descripex.MCP in modules

      for entry <- overview do
        assert entry.annotated? == true
      end
    end

    test "describe(:manifest) returns Level 2 for Manifest" do
      funcs = Descripex.describe(:manifest)

      build = Enum.find(funcs, &(&1.name == :build))
      assert build
      assert build.arity == 1
    end

    test "describe(:describe) returns Level 2 for Describe" do
      funcs = Descripex.describe(:describe)

      desc = Enum.find(funcs, &(&1.name == :describe))
      assert desc
      assert desc.arity == 3
      assert desc.defaults == 2
    end

    test "describe(:manifest, :build) returns Level 3 detail" do
      detail = Descripex.describe(:manifest, :build)

      assert detail.name == :build
      assert detail.arity == 1
      assert detail.description =~ "Build a complete API manifest"
      assert detail.params.modules.kind == :value
      assert detail.returns.type == :map
      assert detail.returns_example == %{version: "1.0", generated_at: "2025-01-01T00:00:00Z", modules: []}
    end

    test "describe(:describe, :describe) returns Level 3 detail with all params" do
      detail = Descripex.describe(:describe, :describe)

      assert detail.name == :describe
      assert detail.arity == 3
      assert detail.params.modules.kind == :value
      assert detail.params.mod_or_short.kind == :value
      assert detail.params.func_name.kind == :value
      assert detail.errors == [argument_error: "Raised when short name is not found or is ambiguous"]
    end

    test "Manifest.__api__/0 returns entry for :build with hints and spec" do
      entries = Descripex.Manifest.__api__()

      assert length(entries) == 1
      build = hd(entries)
      assert build.name == :build
      assert build.arity == 1
      assert is_binary(build.spec)
      assert build.hints.description =~ "Build a complete API manifest"
      assert build.hints.params.modules.kind == :value
    end

    test "Describe.__api__/0 returns entry for :describe with 3 params" do
      entries = Descripex.Describe.__api__()

      assert length(entries) == 1
      desc = hd(entries)
      assert desc.name == :describe
      assert desc.arity == 3
      assert desc.defaults == 2
      assert is_binary(desc.spec)
      assert Map.has_key?(desc.hints.params, :modules)
      assert Map.has_key?(desc.hints.params, :mod_or_short)
      assert Map.has_key?(desc.hints.params, :func_name)
    end

    test "root __api__ stubs return empty data" do
      assert Descripex.__api__() == []
      assert Descripex.__api__(:anything) == nil
    end

    test "Describe.__api__(:describe) param_order preserves declaration order" do
      entry = Descripex.Describe.__api__(:describe)
      assert entry.param_order == [:modules, :mod_or_short, :func_name]
    end
  end

  describe "param_order in __api__" do
    test "param_order lists declared positional params in order, including defaults" do
      Code.compile_string("""
      defmodule ParamOrderBasic do
        use Descripex

        api :greet, "Greet someone.",
          params: [
            name: [kind: :value, description: "Name"],
            enthusiasm: [kind: :value, default: 1, description: "Exclamation count"]
          ]

        def greet(name, enthusiasm \\\\ 1), do: "Hello \#{name}" <> String.duplicate("!", enthusiasm)
      end
      """)

      entry = ParamOrderBasic.__api__(:greet)
      assert entry.param_order == [:name, :enthusiasm]
    after
      :code.purge(ParamOrderBasic)
      :code.delete(ParamOrderBasic)
    end

    test "param_order is [] for a function with no declared params" do
      Code.compile_string("""
      defmodule ParamOrderNone do
        use Descripex

        api :ping, "Health check."

        def ping, do: :pong
      end
      """)

      entry = ParamOrderNone.__api__(:ping)
      assert entry.param_order == []
    after
      :code.purge(ParamOrderNone)
      :code.delete(ParamOrderNone)
    end

    test "named args ordered by param_order round-trip to the correct positional slots" do
      # Params declared in non-alphabetical order. Map.keys/1 on hints.params would
      # return hash order and swap the arguments; param_order must not.
      Code.compile_string("""
      defmodule ParamOrderDispatch do
        use Descripex

        api :list, "List records.",
          params: [
            project_name: [kind: :value, description: "Project name"],
            status: [kind: :value, description: "Status filter"]
          ]

        def list(project_name, status), do: {project_name, status}
      end
      """)

      entry = ParamOrderDispatch.__api__(:list)
      assert entry.param_order == [:project_name, :status]

      # Simulate an MCP/JSON tool call: named args mapped onto positional apply/3.
      named = %{status: "pending", project_name: "rexex"}
      args = Enum.map(entry.param_order, &Map.fetch!(named, &1))

      assert apply(ParamOrderDispatch, :list, args) == {"rexex", "pending"}
    after
      :code.purge(ParamOrderDispatch)
      :code.delete(ParamOrderDispatch)
    end

    test "param_order coexists with the unchanged hints.params map" do
      Code.compile_string("""
      defmodule ParamOrderCoexist do
        use Descripex

        api :add, "Add numbers.",
          params: [
            a: [kind: :value, description: "First"],
            b: [kind: :value, description: "Second"]
          ]

        def add(a, b), do: a + b
      end
      """)

      entry = ParamOrderCoexist.__api__(:add)
      assert entry.param_order == [:a, :b]
      # hints.params remains a map keyed by param name (backward compatible)
      assert is_map(entry.hints.params)
      assert entry.hints.params.a.kind == :value
      assert entry.hints.params.b.kind == :value
    after
      :code.purge(ParamOrderCoexist)
      :code.delete(ParamOrderCoexist)
    end
  end

  describe "emit_api/3 for variable opts" do
    test "declares apis from a for-comprehension with variable opts" do
      Code.compile_string("""
      defmodule EmitApiForComp do
        use Descripex

        for {fname, fdesc} <- [{:alpha, "Alpha function."}, {:beta, "Beta function."}] do
          api_opts = [params: [x: [kind: :value, description: "X value"]]]
          emit_api(fname, fdesc, api_opts)
          def unquote(fname)(x), do: x
        end
      end
      """)

      alpha = EmitApiForComp.__api__(:alpha)
      assert alpha.name == :alpha
      assert alpha.param_order == [:x]
      assert alpha.hints.description == "Alpha function."
      assert alpha.hints.params.x.kind == :value

      beta = EmitApiForComp.__api__(:beta)
      assert beta.name == :beta
      assert beta.param_order == [:x]
      assert beta.hints.description == "Beta function."
    after
      :code.purge(EmitApiForComp)
      :code.delete(EmitApiForComp)
    end

    test "api/3 cannot serve variable opts — proving the gap emit_api/3 fills" do
      # preprocess_schemas/1 calls Keyword.get/3 (is_list guard) on the opts AST,
      # which is a 3-tuple var node here, not a list — so api/3 raises at expansion.
      assert_raise FunctionClauseError, fn ->
        Code.compile_string("""
        defmodule ApiVarOptsFail do
          use Descripex

          for {fname, fdesc} <- [{:alpha, "Alpha."}] do
            api_opts = [params: [x: [kind: :value, description: "X value"]]]
            api(fname, fdesc, api_opts)
            def unquote(fname)(x), do: x
          end
        end
        """)
      end
    end

    test "emit_api/3 and api/3 emit identical @doc text and hints for literal opts" do
      api_docs =
        compile_and_fetch_docs("""
        defmodule ApiLiteral do
          use Descripex

          api :run, "Run the thing.",
            params: [n: [kind: :value, description: "How many"]],
            opts: [verbose: [type: :boolean, description: "Chatty"]],
            returns: %{type: :integer, description: "Count"}

          def run(n, opts \\\\ []), do: {n, opts}
        end
        """)

      emit_docs =
        compile_and_fetch_docs("""
        defmodule EmitLiteral do
          use Descripex

          run_opts = [
            params: [n: [kind: :value, description: "How many"]],
            opts: [verbose: [type: :boolean, description: "Chatty"]],
            returns: %{type: :integer, description: "Count"}
          ]

          emit_api(:run, "Run the thing.", run_opts)

          def run(n, opts \\\\ []), do: {n, opts}
        end
        """)

      {_, _, _, %{"en" => api_text}, %{hints: api_hints}} = find_func_doc(api_docs, :run, 2)
      {_, _, _, %{"en" => emit_text}, %{hints: emit_hints}} = find_func_doc(emit_docs, :run, 2)

      assert emit_text == api_text
      assert emit_hints == api_hints
    after
      :code.purge(ApiLiteral)
      :code.delete(ApiLiteral)
      :code.purge(EmitLiteral)
      :code.delete(EmitLiteral)
    end

    test "compile-time validation fires for emit_api/3 (wrong param name raises)" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule EmitBadParam do
          use Descripex

          o = [params: [wrong_name: [kind: :value, description: "X"]]]
          emit_api(:run, "Run.", o)

          def run(actual_name), do: actual_name
        end
        """)
      end
    end

    test "emit_api/3 rejects a literal keyword-list opts, steering to api/3" do
      assert_raise ArgumentError, ~r/use api\/3 instead/, fn ->
        Code.compile_string("""
        defmodule EmitLiteralReject do
          use Descripex

          emit_api(:run, "Run.", params: [n: [kind: :value, description: "N"]])

          def run(n), do: n
        end
        """)
      end
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

    test "renders composes_with in doc text, hints, and contract" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocGenComposesWith do
          use Descripex

          api :execute, "Execute operation.",
            params: [
              input: [kind: :value, description: "Input"]
            ],
            composes_with: [:normalize, :persist]

          def execute(input), do: persist(normalize(input))
          def normalize(input), do: input
          def persist(input), do: {:ok, input}
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :execute, 1)
      contract = parse_contract(doc_text)

      assert doc_text =~ "## Composes With"
      assert doc_text =~ "  * `normalize`"
      assert doc_text =~ "  * `persist`"
      assert metadata.hints.composes_with == [:normalize, :persist]
      assert contract.composes_with == [:normalize, :persist]
    after
      :code.purge(DocGenComposesWith)
      :code.delete(DocGenComposesWith)
    end
  end

  describe "manual @doc coexistence with api()" do
    test "manual @doc after api() overwrites doc text but preserves hints metadata" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocCoexistManual do
          use Descripex

          api :imbalance!, "Calculate orderbook imbalance (raises on error).",
            params: [
              orderbook: [kind: :exchange_data, description: "Orderbook data"],
              depth: [kind: :value, default: 10, description: "Depth levels"]
            ],
            returns: %{type: :float, description: "Imbalance ratio"}

          @doc "Bang variant of `imbalance/2`. Returns the float directly or raises on error."
          def imbalance!(orderbook, _depth \\\\ 10), do: orderbook[:ratio] || raise "no data"
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :imbalance!, 2)

      # Slot 4: manual @doc text wins (overwrites api()-generated text)
      assert doc_text == "Bang variant of `imbalance/2`. Returns the float directly or raises on error."
      refute doc_text =~ "## Parameters"
      refute doc_text =~ "## Returns"

      # Slot 5: hints metadata from api() survives untouched
      assert %{hints: hints} = metadata
      assert hints.description == "Calculate orderbook imbalance (raises on error)."
      assert hints.params.orderbook.kind == :exchange_data
      assert hints.params.depth.kind == :value
      assert hints.params.depth.default == 10
      assert hints.returns.type == :float
    after
      :code.purge(DocCoexistManual)
      :code.delete(DocCoexistManual)
    end

    test "api() without subsequent manual @doc writes both slots" do
      docs =
        compile_and_fetch_docs("""
        defmodule DocCoexistDefault do
          use Descripex

          api :ping, "Health check.",
            returns: %{type: :atom, description: "Always :pong"}

          def ping, do: :pong
        end
        """)

      {_, _, _, %{"en" => doc_text}, metadata} = find_func_doc(docs, :ping, 0)

      # Slot 4: api()-generated text (has sections)
      assert doc_text =~ "Health check."
      assert doc_text =~ "## Returns"

      # Slot 5: hints metadata
      assert %{hints: hints} = metadata
      assert hints.description == "Health check."
      assert hints.returns.type == :atom
    after
      :code.purge(DocCoexistDefault)
      :code.delete(DocCoexistDefault)
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

    test "multi-arity function validates against matching arity clause" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidMultiArity do
          use Descripex

          api :fetch, "Fetch by list.",
            params: [
              list: [kind: :value, description: "List of items"]
            ]

          def fetch(list) when is_list(list), do: list
          def fetch(map, key) when is_map(map), do: Map.get(map, key)
        end
        """)

      # api() attaches hints to the immediately following def (arity 1)
      {_, _, _, _, metadata} = find_func_doc(docs, :fetch, 1)
      assert %{hints: %{params: %{list: _}}} = metadata
    after
      :code.purge(ValidMultiArity)
      :code.delete(ValidMultiArity)
    end

    test "multi-arity with different param names at same position compiles" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidMultiArityDiffNames do
          use Descripex

          api :convert, "Convert a map.",
            params: [
              map: [kind: :value, description: "Map to convert"],
              key: [kind: :value, description: "Key to extract"]
            ]

          def convert(list) when is_list(list), do: list
          def convert(map, key) when is_map(map), do: Map.get(map, key)
        end
        """)

      # api() attaches hints to the immediately following def (arity 1)
      # but validates declared params against arity-2 clause successfully
      {_, _, _, _, metadata} = find_func_doc(docs, :convert, 1)
      assert %{hints: %{params: %{map: _, key: _}}} = metadata
    after
      :code.purge(ValidMultiArityDiffNames)
      :code.delete(ValidMultiArityDiffNames)
    end

    test "multi-arity reports max arity in __api__/0" do
      compile_and_fetch_docs("""
      defmodule MultiArityApi do
        use Descripex

        api :process, "Process data.",
          params: [
            data: [kind: :value, description: "Data input"]
          ]

        def process(data) when is_list(data), do: data
        def process(data, opts) when is_list(data), do: {data, opts}
      end
      """)

      mod = MultiArityApi
      [entry] = mod.__api__()
      assert entry.name == :process
      assert entry.arity == 2
    after
      :code.purge(MultiArityApi)
      :code.delete(MultiArityApi)
    end

    test "multi-arity with defaults still validates correctly" do
      docs =
        compile_and_fetch_docs("""
        defmodule MultiArityDefaults do
          use Descripex

          api :greet, "Greet someone.",
            params: [
              name: [kind: :value, description: "Name to greet"]
            ]

          def greet(name, enthusiasm \\\\ 1) do
            "Hello \#{name}" <> String.duplicate("!", enthusiasm)
          end
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :greet, 2)
      assert %{hints: %{params: %{name: _}}} = metadata
    after
      :code.purge(MultiArityDefaults)
      :code.delete(MultiArityDefaults)
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

    test "composes_with validates when referenced functions exist in module" do
      docs =
        compile_and_fetch_docs("""
        defmodule ValidComposesWith do
          use Descripex

          api :execute, "Execute operation.",
            composes_with: [:normalize, :persist]

          def execute(input), do: persist(normalize(input))
          def normalize(input), do: input
          def persist(input), do: {:ok, input}
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :execute, 1)
      assert metadata.hints.composes_with == [:normalize, :persist]
    after
      :code.purge(ValidComposesWith)
      :code.delete(ValidComposesWith)
    end

    test "raises CompileError when composes_with references missing function" do
      assert_raise CompileError,
                   ~r/api :execute composes_with function :missing has no matching def in module/,
                   fn ->
                     Code.compile_string("""
                     defmodule InvalidComposesWithMissing do
                       use Descripex

                       api :execute, "Execute operation.",
                         composes_with: [:missing]

                       def execute(input), do: input
                     end
                     """)
                   end
    after
      :code.purge(InvalidComposesWithMissing)
      :code.delete(InvalidComposesWithMissing)
    end

    test "raises CompileError when composes_with contains non-atom entry" do
      assert_raise CompileError,
                   ~r/api :execute composes_with entries must be atoms, got: "normalize"/,
                   fn ->
                     Code.compile_string("""
                     defmodule InvalidComposesWithType do
                       use Descripex

                       api :execute, "Execute operation.",
                         composes_with: ["normalize"]

                       def execute(input), do: input
                     end
                     """)
                   end
    after
      :code.purge(InvalidComposesWithType)
      :code.delete(InvalidComposesWithType)
    end
  end

  describe "multi-arity BEAM docs chunk behavior" do
    test "all arities have hints in BEAM docs chunk for 2-arity function" do
      docs =
        compile_and_fetch_docs("""
        defmodule MultiArityHintsChunk do
          use Descripex

          api :greet, "Say hello.",
            params: [
              name: [kind: :value, description: "Name"],
              opts: [kind: :value, default: [], description: "Options"]
            ]

          def greet(name), do: greet(name, [])
          def greet(name, opts), do: "Hello \#{name} \#{inspect(opts)}"
        end
        """)

      for arity <- 1..2 do
        {_, _, _, _, meta} = find_func_doc(docs, :greet, arity)
        assert %{hints: %{params: %{name: _}}} = meta, "greet/#{arity} missing hints"
      end
    after
      :code.purge(MultiArityHintsChunk)
      :code.delete(MultiArityHintsChunk)
    end

    test "all arities have hints in BEAM docs chunk for 3-arity function" do
      docs =
        compile_and_fetch_docs("""
        defmodule MultiArityHints3 do
          use Descripex

          api :greet, "Say hello.",
            params: [
              name: [kind: :value, description: "Name"],
              greeting: [kind: :value, default: "Hello", description: "Greeting prefix"],
              opts: [kind: :value, default: [], description: "Options"]
            ]

          @doc "Greets someone."
          def greet(name), do: greet(name, "Hello", [])
          def greet(name, greeting), do: greet(name, greeting, [])
          def greet(name, greeting, _opts), do: "\#{greeting} \#{name}"
        end
        """)

      for arity <- 1..3 do
        {_, _, _, _, meta} = find_func_doc(docs, :greet, arity)
        assert %{hints: hints} = meta, "greet/#{arity} missing hints in metadata"
        assert hints.description == "Say hello."
        assert hints.params.name.kind == :value
      end
    after
      :code.purge(MultiArityHints3)
      :code.delete(MultiArityHints3)
    end

    test "__api__/0 reports max arity with correct hints for true multi-arity" do
      compile_and_fetch_docs("""
      defmodule MultiArityApiHints do
        use Descripex

        api :greet, "Say hello.",
          params: [
            name: [kind: :value, description: "Name"],
            opts: [kind: :value, default: [], description: "Options"]
          ]

        def greet(name), do: greet(name, [])
        def greet(name, opts), do: "Hello \#{name} \#{inspect(opts)}"
      end
      """)

      mod = MultiArityApiHints
      [entry] = mod.__api__()
      assert entry.name == :greet
      assert entry.arity == 2
      assert entry.hints.description == "Say hello."
      assert entry.hints.params.name.kind == :value
      assert entry.hints.params.opts.kind == :value
    after
      :code.purge(MultiArityApiHints)
      :code.delete(MultiArityApiHints)
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

  describe "schema option" do
    @tag :schema
    test "schema: in params produces JSON Schema in hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaBasicParams do
          use Descripex

          api :add, "Add two numbers.",
            params: [
              a: [kind: :value, description: "First number", schema: float()],
              b: [kind: :value, description: "Second number", schema: integer()]
            ]

          def add(a, b), do: a + b
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :add, 2)

      assert %{hints: hints} = metadata
      assert hints.params.a.schema == %{"type" => "number"}
      assert hints.params.b.schema == %{"type" => "integer"}
    after
      :code.purge(SchemaBasicParams)
      :code.delete(SchemaBasicParams)
    end

    @tag :schema
    test "schema: in opts produces JSON Schema in hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaOpts do
          use Descripex

          api :fetch, "Fetch data.",
            params: [
              id: [kind: :value, description: "Record ID", schema: String.t()]
            ],
            opts: [
              limit: [type: :integer, default: 10, description: "Max results", schema: pos_integer()]
            ]

          def fetch(_id, _opts \\\\ []), do: {:ok, []}
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :fetch, 2)

      assert %{hints: hints} = metadata
      assert hints.params.id.schema == %{"type" => "string"}
      assert hints.opts.limit.schema == %{"type" => "integer", "minimum" => 1}
    after
      :code.purge(SchemaOpts)
      :code.delete(SchemaOpts)
    end

    @tag :schema
    test "complex schema types: maps, lists, enums" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaComplex do
          use Descripex

          api :process, "Process data.",
            params: [
              items: [kind: :value, description: "Item list", schema: [String.t()]],
              side: [kind: :value, description: "Trade side", schema: :buy | :sell],
              config: [kind: :value, description: "Config map", schema: %{name: String.t(), count: integer()}]
            ]

          def process(_items, _side, _config), do: :ok
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :process, 3)

      assert %{hints: hints} = metadata
      assert hints.params.items.schema == %{"type" => "array", "items" => %{"type" => "string"}}
      assert hints.params.side.schema == %{"type" => "string", "enum" => ["buy", "sell"]}

      assert hints.params.config.schema == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "count" => %{"type" => "integer"}
               },
               "required" => ["name", "count"],
               "additionalProperties" => false
             }
    after
      :code.purge(SchemaComplex)
      :code.delete(SchemaComplex)
    end

    @tag :schema
    test "params without schema: are backwards compatible" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaBackcompat do
          use Descripex

          api :ping, "Health check.",
            params: [
              target: [kind: :value, description: "Target host"]
            ]

          def ping(_target), do: :pong
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :ping, 1)

      assert %{hints: hints} = metadata
      refute Map.has_key?(hints.params.target, :schema)
    after
      :code.purge(SchemaBackcompat)
      :code.delete(SchemaBackcompat)
    end

    @tag :schema
    test "a @spec arg type JSONSpec cannot express is skipped, not crashed" do
      # JSONSpec raises (CaseClauseError / FunctionClauseError, not ArgumentError)
      # on compound types its clauses don't match — e.g. a map field whose value is
      # a sized bitstring. safe_convert/1 must skip the param rather than let the
      # exception abort the whole enrich_with_specs/manifest/describe build.
      # Regression: descripex 0.9.0 only rescued ArgumentError, so real-world specs
      # like Cartouche's `%{required(non_neg_integer()) => <<_::256>>}` crashed.
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaUnconvertible do
          use Descripex

          api :store, "Store words by slot.",
            params: [
              words: [kind: :value, description: "Slot to 32-byte word map"]
            ]

          @spec store(%{required(non_neg_integer()) => <<_::256>>}) :: :ok
          def store(_words), do: :ok
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :store, 1)

      assert %{hints: hints} = metadata
      refute Map.has_key?(hints.params.words, :schema)
    after
      :code.purge(SchemaUnconvertible)
      :code.delete(SchemaUnconvertible)
    end

    @tag :schema
    test "schema appears in __api__/0 output" do
      Code.compile_string("""
      defmodule SchemaApiIntrospect do
        use Descripex

        api :calc, "Calculate.",
          params: [
            value: [kind: :value, description: "Input value", schema: float()]
          ]

        def calc(_value), do: 0.0
      end
      """)

      mod = SchemaApiIntrospect
      [entry] = mod.__api__()
      assert entry.hints.params.value.schema == %{"type" => "number"}
    after
      :code.purge(SchemaApiIntrospect)
      :code.delete(SchemaApiIntrospect)
    end

    @tag :schema
    test "__api__/0 hints and the doc chunk diverge on spec-injected schema, reconciled by normalize_for_doc_compare/1" do
      # AnnotatedFixture.add/2 has schema-less params with @spec add(number(), number()):
      # __api__/0 enriches them with spec-derived schemas at runtime, but the
      # compile-time doc chunk does not. Pins Option B (the asymmetry is intentional)
      # AND the normalizer contract. Uses an on-disk fixture because runtime spec
      # enrichment needs Code.Typespec.fetch_specs/1, which returns :error for
      # Code.compile_string modules (no persisted spec chunk).
      alias Descripex.Test.AnnotatedFixture

      api_hints = AnnotatedFixture.__api__(:add).hints

      {:docs_v1, _, _, _, _, _, func_docs} = Code.fetch_docs(AnnotatedFixture)

      {_, _, _, _, metadata} =
        Enum.find(func_docs, fn
          {{:function, :add, 2}, _, _, _, _} -> true
          _ -> false
        end)

      meta_hints = metadata.hints

      # Asymmetry: __api__/0 gained the spec-derived schema, the doc chunk did not.
      assert api_hints.params.a.schema == %{"type" => "number"}
      refute Map.has_key?(meta_hints.params.a, :schema)
      refute api_hints == meta_hints

      # Normalizer reconciles: equal once schema is stripped from both surfaces.
      assert Descripex.normalize_for_doc_compare(api_hints) ==
               Descripex.normalize_for_doc_compare(meta_hints)
    end

    @tag :schema
    test "normalize_for_doc_compare/1 strips author-declared schemas from params, opts, and returns" do
      # Author-declared schemas are indistinguishable from spec-injected ones, so
      # the normalizer drops them too — documenting that it is a blanket strip.
      # Hand-built in the post-conversion hints shape (schema values are already
      # JSON Schema maps), since `schema: float()` syntax only works in the macro.
      hints = %{
        description: "Fetch data.",
        params: %{id: %{kind: :value, description: "Record ID", schema: %{"type" => "string"}}},
        opts: %{
          limit: %{
            type: :integer,
            default: 10,
            description: "Max results",
            schema: %{"type" => "integer", "minimum" => 1}
          }
        },
        returns: %{type: :float, description: "Result", schema: %{"type" => "number"}}
      }

      normalized = Descripex.normalize_for_doc_compare(hints)

      refute Map.has_key?(normalized.params.id, :schema)
      refute Map.has_key?(normalized.opts.limit, :schema)
      refute Map.has_key?(normalized.returns, :schema)

      # Non-schema fields are untouched.
      assert normalized.params.id.description == "Record ID"
      assert normalized.opts.limit.type == :integer
      assert normalized.returns.type == :float
    end

    @tag :schema
    test "normalize_for_doc_compare/1 is a no-op on hints with no params/opts/returns" do
      hints = Descripex.build_hints("Just a description.", [])
      assert Descripex.normalize_for_doc_compare(hints) == hints
    end

    @tag :schema
    test "schema: in returns produces JSON Schema in hints" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaReturns do
          use Descripex

          api :calc, "Calculate.",
            params: [
              value: [kind: :value, description: "Input"]
            ],
            returns: %{type: :float, description: "Result", schema: float()}

          def calc(_value), do: 0.0
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :calc, 1)

      assert %{hints: hints} = metadata
      assert hints.returns.schema == %{"type" => "number"}
      assert hints.returns.type == :float
      assert hints.returns.description == "Result"
    after
      :code.purge(SchemaReturns)
      :code.delete(SchemaReturns)
    end

    @tag :schema
    test "returns without schema: is backwards compatible" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaReturnsBackcompat do
          use Descripex

          api :ping, "Ping.",
            returns: %{type: :atom, description: "Always :pong"}

          def ping, do: :pong
        end
        """)

      {_, _, _, _, metadata} = find_func_doc(docs, :ping, 0)

      assert %{hints: hints} = metadata
      refute Map.has_key?(hints.returns, :schema)
      assert hints.returns.type == :atom
    after
      :code.purge(SchemaReturnsBackcompat)
      :code.delete(SchemaReturnsBackcompat)
    end

    @tag :schema
    test "returns schema appears in __api__/0 output" do
      Code.compile_string("""
      defmodule SchemaReturnsApi do
        use Descripex

        api :calc, "Calculate.",
          params: [
            value: [kind: :value, description: "Input"]
          ],
          returns: %{type: :float, description: "Result", schema: float()}

        def calc(_value), do: 0.0
      end
      """)

      mod = SchemaReturnsApi
      [entry] = mod.__api__()
      assert entry.hints.returns.schema == %{"type" => "number"}
    after
      :code.purge(SchemaReturnsApi)
      :code.delete(SchemaReturnsApi)
    end

    @tag :schema
    test "schema appears in contract block" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaContract do
          use Descripex

          api :calc, "Calculate.",
            params: [
              value: [kind: :value, description: "Input", schema: number()]
            ],
            returns: %{type: :float, description: "Result"}

          def calc(_value), do: 0.0
        end
        """)

      {_, _, _, %{"en" => doc_text}, _} = find_func_doc(docs, :calc, 1)

      contract = parse_contract(doc_text)
      assert contract.params.value.schema == %{"type" => "number"}
    after
      :code.purge(SchemaContract)
      :code.delete(SchemaContract)
    end

    @tag :schema
    test "returns schema appears in contract block" do
      docs =
        compile_and_fetch_docs("""
        defmodule SchemaReturnsContract do
          use Descripex

          api :calc, "Calculate.",
            params: [
              value: [kind: :value, description: "Input"]
            ],
            returns: %{type: :float, description: "Result", schema: float()}

          def calc(_value), do: 0.0
        end
        """)

      {_, _, _, %{"en" => doc_text}, _} = find_func_doc(docs, :calc, 1)

      contract = parse_contract(doc_text)
      assert contract.returns.schema == %{"type" => "number"}
    after
      :code.purge(SchemaReturnsContract)
      :code.delete(SchemaReturnsContract)
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
