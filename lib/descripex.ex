defmodule Descripex do
  @moduledoc """
  Single-source API declarations for self-describing Elixir functions.

  The `api` macro is the sole source of truth for function documentation.
  It generates `@doc` text, emits `@doc hints:` metadata for machine consumption,
  validates param names at compile time, and produces `__api__/0` and `__api__/1`
  introspection functions.

  ## Usage

      defmodule MyLib.Funding do
        use Descripex, namespace: "/funding"

        api(:annualize, "Annualize a per-period funding rate to APR.",
          params: [
            rate: [kind: :value, description: "Per-period funding rate as decimal"],
            period_hours: [kind: :value, default: 8, description: "Hours per period"]
          ],
          returns: %{type: :float, description: "Annualized percentage rate (APR)"}
        )

        @spec annualize(number(), pos_integer()) :: float()
        def annualize(rate, period_hours \\\\ 8), do: ...
      end

  No separate `@doc` block needed — the macro generates it from the declaration.

  ## Introspection

      MyLib.Funding.__api__()
      # => [%{name: :annualize, arity: 2, ...}, ...]

      MyLib.Funding.__api__(:annualize)
      # => %{name: :annualize, arity: 2, spec: "...", hints: %{...}}

  """

  use Descripex.Discoverable, modules: [Descripex.Manifest, Descripex.Describe]

  @doc false
  defmacro __using__(opts) do
    namespace = Keyword.get(opts, :namespace)

    quote do
      import Descripex, only: [api: 2, api: 3]

      Module.register_attribute(__MODULE__, :descripex_api_declarations, accumulate: true)
      @before_compile Descripex

      if unquote(namespace) do
        @moduledoc namespace: unquote(namespace)
      end
    end
  end

  @doc false
  defmacro api(name, description, opts) do
    quote do
      @descripex_api_declarations {unquote(name), unquote(description), unquote(opts)}
      @doc Descripex.generate_doc(unquote(description), unquote(opts))
      @doc hints: Descripex.build_hints(unquote(description), unquote(opts))
    end
  end

  @doc false
  defmacro api(name, description) do
    quote do
      @descripex_api_declarations {unquote(name), unquote(description), []}
      @doc Descripex.generate_doc(unquote(description), [])
      @doc hints: Descripex.build_hints(unquote(description), [])
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    declarations = Module.get_attribute(env.module, :descripex_api_declarations)
    defs = Module.definitions_in(env.module, :def)
    table = build_api_functions_table(declarations, defs)
    moduledoc = Module.get_attribute(env.module, :moduledoc)
    updated_moduledoc = append_api_table_to_moduledoc(moduledoc, table)

    for {name, _desc, opts} <- declarations do
      validate_declaration!(env, name, opts, defs)
    end

    # Build entries at compile time (without specs — can't access own specs yet)
    api_entries =
      Enum.map(declarations, fn {name, description, opts} ->
        {arity, defaults} = find_arity_and_defaults(name, defs)

        %{
          name: name,
          arity: arity,
          defaults: defaults,
          hints: build_hints(description, opts)
        }
      end)

    quote do
      unquote(write_moduledoc_quote(updated_moduledoc))

      @doc false
      @spec __api__() :: [map()]
      def __api__ do
        Descripex.enrich_with_specs(__MODULE__, unquote(Macro.escape(api_entries)))
      end

      @doc false
      @spec __api__(atom()) :: map() | nil
      def __api__(name) do
        Enum.find(__api__(), &(&1.name == name))
      end
    end
  end

  # Stubs required because Doctor's AST walker finds `def __api__` inside
  # the __before_compile__ quote block and counts them as Descripex functions.
  @doc false
  @spec __api__() :: [map()]
  def __api__, do: []

  @doc false
  @spec __api__(atom()) :: map() | nil
  def __api__(_name), do: nil

  # --- Public helpers (called at compile time of using module) ---

  @doc "Generate human-readable `@doc` text from an api declaration's description and options."
  @spec generate_doc(String.t(), keyword()) :: String.t()
  def generate_doc(description, opts) do
    params = Keyword.get(opts, :params, [])
    opt_params = Keyword.get(opts, :opts, [])
    returns = Keyword.get(opts, :returns)
    returns_example = Keyword.get(opts, :returns_example)
    errors = Keyword.get(opts, :errors, [])
    composes_with = Keyword.get(opts, :composes_with, [])
    contract = description |> build_hints(opts) |> Map.delete(:description)

    [
      escape_doc(description),
      format_params_section(params),
      format_opts_section(opt_params),
      format_returns_section(returns, returns_example),
      format_errors_section(errors),
      format_composes_with_section(composes_with),
      format_contract_block(contract)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc "Build machine-readable hints map from an api declaration's description and options."
  @spec build_hints(String.t(), keyword()) :: map()
  def build_hints(description, opts) do
    params = Keyword.get(opts, :params, [])
    opt_params = Keyword.get(opts, :opts, [])
    returns = Keyword.get(opts, :returns)
    returns_example = Keyword.get(opts, :returns_example)
    errors = Keyword.get(opts, :errors)
    composes_with = Keyword.get(opts, :composes_with)

    %{description: description}
    |> put_if_present(:params, build_params_map(params))
    |> put_if_present(:opts, build_params_map(opt_params))
    |> put_if_present(:returns, returns)
    |> put_if_present(:returns_example, returns_example)
    |> put_if_present(:errors, errors)
    |> put_if_present(:composes_with, composes_with)
  end

  @doc """
  Enrich compile-time api entries with specs fetched at runtime.
  """
  @spec enrich_with_specs(module(), [map()]) :: [map()]
  def enrich_with_specs(module, entries) do
    specs =
      case Code.Typespec.fetch_specs(module) do
        {:ok, specs} -> Map.new(specs)
        _ -> %{}
      end

    Enum.map(entries, fn entry ->
      Map.put(entry, :spec, format_spec(entry.name, entry.arity, specs))
    end)
  end

  # --- Doc generation ---

  @doc false
  # Escapes curly braces in description strings to prevent ExDoc/Earmark IAL warnings.
  # Braces inside backtick code spans (e.g., `{:ok, val}`) are left as-is since
  # Earmark doesn't treat them as IAL inside inline code.
  defp escape_doc(text) do
    text
    |> String.split("`")
    |> escape_alternating(true, [])
    |> Enum.reverse()
    |> Enum.join("`")
  end

  @doc false
  defp escape_alternating([], _outside?, acc), do: acc

  defp escape_alternating([segment | rest], true, acc) do
    escaped = String.replace(segment, ~r/[{}]/, "\\\\\\0")
    escape_alternating(rest, false, [escaped | acc])
  end

  defp escape_alternating([segment | rest], false, acc) do
    escape_alternating(rest, true, [segment | acc])
  end

  @doc false
  defp format_params_section([]), do: nil

  defp format_params_section(params) do
    lines =
      Enum.map(params, fn {name, details} ->
        desc = Keyword.get(details, :description, "")
        default = Keyword.get(details, :default)
        kind = Keyword.get(details, :kind)

        suffix = build_param_suffix(kind, default)
        "  * `#{name}` - #{escape_doc(desc)}#{suffix}"
      end)

    "## Parameters\n\n" <> Enum.join(lines, "\n")
  end

  @doc false
  defp format_opts_section([]), do: nil

  defp format_opts_section(opt_params) do
    lines =
      Enum.map(opt_params, fn {name, details} ->
        desc = Keyword.get(details, :description, "")
        default = Keyword.get(details, :default)
        default_str = if default == nil, do: "", else: " (default: `#{inspect(default)}`)"
        "  * `#{name}` - #{escape_doc(desc)}#{default_str}"
      end)

    "## Options\n\n" <> Enum.join(lines, "\n")
  end

  @doc false
  defp format_returns_section(nil, nil), do: nil

  defp format_returns_section(%{} = returns, nil) do
    desc = Map.get(returns, :description, "")
    type = Map.get(returns, :type)
    type_str = if type, do: " (`#{type}`)", else: ""
    "## Returns\n\n#{escape_doc(desc)}#{type_str}"
  end

  defp format_returns_section(%{} = returns, returns_example) do
    desc = Map.get(returns, :description, "")
    type = Map.get(returns, :type)
    type_str = if type, do: " (`#{type}`)", else: ""

    "## Returns\n\n#{escape_doc(desc)}#{type_str}\n\n#{format_returns_example(returns_example)}"
  end

  defp format_returns_section(nil, returns_example) do
    "## Returns\n\n#{format_returns_example(returns_example)}"
  end

  @doc false
  defp format_errors_section([]), do: nil

  defp format_errors_section(errors) do
    lines =
      Enum.map(errors, fn
        name when is_atom(name) ->
          "  * `#{inspect(name)}`"

        {name, description} ->
          "  * `#{inspect(name)}` - #{escape_doc(description)}"
      end)

    "## Errors\n\n" <> Enum.join(lines, "\n")
  end

  @doc false
  defp format_composes_with_section([]), do: nil

  defp format_composes_with_section(composes_with) do
    lines =
      Enum.map(composes_with, fn name ->
        "  * `#{name}`"
      end)

    "## Composes With\n\n" <> Enum.join(lines, "\n")
  end

  @doc false
  defp format_contract_block(contract) do
    contract_literal = inspect(contract, pretty: true, limit: :infinity)
    "```elixir\n# descripex:contract\n#{contract_literal}\n```"
  end

  @doc false
  defp format_returns_example(returns_example) do
    literal = inspect(returns_example, pretty: true, limit: :infinity)
    "### Example\n\n```elixir\n#{literal}\n```"
  end

  @doc false
  defp build_param_suffix(kind, default) do
    parts = []
    parts = if default == nil, do: parts, else: ["default: `#{inspect(default)}`" | parts]
    parts = if kind, do: [Atom.to_string(kind) | parts], else: parts

    case parts do
      [] -> ""
      _ -> " (" <> Enum.join(Enum.reverse(parts), ", ") <> ")"
    end
  end

  # --- Hints map ---

  @doc false
  defp build_params_map([]), do: nil

  defp build_params_map(params) do
    Map.new(params, fn {name, details} ->
      {name, Map.new(details)}
    end)
  end

  @doc false
  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  # --- Spec formatting (called at runtime) ---

  @doc false
  defp format_spec(name, arity, specs) do
    case Map.get(specs, {name, arity}) do
      nil ->
        nil

      [spec_ast | _] ->
        name
        |> Code.Typespec.spec_to_quoted(spec_ast)
        |> Macro.to_string()
    end
  end

  # --- Compile-time helpers ---

  @doc false
  defp find_arity_and_defaults(name, defs) do
    matching = Enum.filter(defs, fn {def_name, _} -> def_name == name end)

    case matching do
      [] ->
        {0, 0}

      arities ->
        max_arity = arities |> Enum.map(&elem(&1, 1)) |> Enum.max()
        min_arity = arities |> Enum.map(&elem(&1, 1)) |> Enum.min()
        {max_arity, max_arity - min_arity}
    end
  end

  # --- Compile-time validation ---

  @doc false
  defp validate_declaration!(env, name, opts, defs) do
    matching = Enum.filter(defs, fn {def_name, _arity} -> def_name == name end)

    if Enum.empty?(matching) do
      raise CompileError,
        file: env.file,
        line: 0,
        description: "api declaration for :#{name} has no matching def"
    end

    validate_composes_with!(env, name, opts, defs)

    {_, max_arity} = Enum.max_by(matching, fn {_, arity} -> arity end)
    validate_params!(env, name, max_arity, opts)
  end

  @doc false
  # Validates intra-module function composition declarations for api/3.
  defp validate_composes_with!(env, name, opts, defs) do
    composes_with = Keyword.get(opts, :composes_with, [])
    defined_names = MapSet.new(defs, &elem(&1, 0))

    Enum.each(composes_with, fn
      composed_name when is_atom(composed_name) ->
        if MapSet.member?(defined_names, composed_name) do
          :ok
        else
          raise CompileError,
            file: env.file,
            line: 0,
            description: "api :#{name} composes_with function :#{composed_name} has no matching def in module"
        end

      invalid ->
        raise CompileError,
          file: env.file,
          line: 0,
          description: "api :#{name} composes_with entries must be atoms, got: #{inspect(invalid)}"
    end)
  end

  @doc false
  defp validate_params!(env, name, arity, opts) do
    declared_params = Keyword.get(opts, :params, [])

    if declared_params != [] do
      {:v1, :def, _meta, clauses} = Module.get_definition(env.module, {name, arity})

      actual_names = extract_param_names(clauses)
      declared_names = Keyword.keys(declared_params)

      validate_param_match!(env, name, declared_names, actual_names)
    end
  end

  @doc false
  defp extract_param_names(clauses) do
    all_names = Enum.map(clauses, &extract_clause_param_names/1)
    max_params = all_names |> Enum.map(&length/1) |> Enum.max()

    Enum.map(0..(max_params - 1), fn idx ->
      all_names
      |> Enum.map(&Enum.at(&1, idx))
      |> Enum.find(:_pattern, &(&1 != :_pattern))
    end)
  end

  @doc false
  defp extract_clause_param_names({_meta, args, _guards, _body}) do
    Enum.map(args, fn
      {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
        if String.starts_with?(Atom.to_string(name), "_"), do: :_pattern, else: name

      {:\\, _, [{name, _, _}, _default]} when is_atom(name) ->
        name

      _ ->
        :_pattern
    end)
  end

  @doc false
  defp validate_param_match!(env, func_name, declared_names, actual_names) do
    Enum.each(Enum.with_index(declared_names), fn {declared, idx} ->
      actual = Enum.at(actual_names, idx)

      cond do
        actual == declared -> :ok
        actual == :_pattern -> :ok
        true -> raise_param_mismatch!(env, func_name, declared, idx, actual)
      end
    end)
  end

  @doc false
  defp raise_param_mismatch!(env, name, declared, idx, actual) do
    raise CompileError,
      file: env.file,
      line: 0,
      description:
        "api :#{name} param :#{declared} at position #{idx} " <>
          "doesn't match def param :#{actual}"
  end

  @doc false
  defp append_api_table_to_moduledoc(nil, table), do: table

  defp append_api_table_to_moduledoc({_, nil}, table), do: table
  defp append_api_table_to_moduledoc(false, _table), do: false
  defp append_api_table_to_moduledoc({_, false}, _table), do: false

  defp append_api_table_to_moduledoc({_, text}, table) when is_binary(text) do
    text <> "\n\n" <> table
  end

  @doc false
  defp write_moduledoc_quote(false), do: quote(do: nil)

  defp write_moduledoc_quote(text) when is_binary(text) do
    quote do
      @moduledoc unquote(text)
    end
  end

  @doc false
  defp build_api_functions_table(declarations, defs) do
    rows =
      Enum.map(declarations, fn {name, description, opts} ->
        {arity, _defaults} = find_arity_and_defaults(name, defs)
        param_kinds = format_param_kinds(Keyword.get(opts, :params, []))

        "| `#{name}` | #{arity} | #{escape_table_cell(description)} | #{param_kinds} |"
      end)

    Enum.join(
      [
        "## API Functions",
        "| Function | Arity | Description | Param Kinds |",
        "| --- | --- | --- | --- |",
        Enum.join(rows, "\n")
      ],
      "\n"
    )
  end

  @doc false
  defp format_param_kinds([]), do: "-"

  defp format_param_kinds(params) do
    kinds =
      Enum.flat_map(params, fn {name, details} ->
        case Keyword.get(details, :kind) do
          nil -> []
          kind -> ["`#{name}: #{kind}`"]
        end
      end)

    case kinds do
      [] -> "-"
      _ -> Enum.join(kinds, ", ")
    end
  end

  @doc false
  defp escape_table_cell(text) do
    text
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace("\n", "<br>")
  end
end
