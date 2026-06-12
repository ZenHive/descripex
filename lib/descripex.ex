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
      # => %{name: :annualize, arity: 2, param_order: [:rate, :period_hours], spec: "...", hints: %{...}}

  The `param_order` field lists the positional parameter names in declaration
  order (including defaulted params). Consumers that dispatch named arguments
  positionally — e.g. mapping MCP/JSON tool arguments onto
  `apply(module, fun, args)` — **must** order arguments by `param_order`, not by
  `Map.keys(hints.params)`. The `hints[:params]` map discards declaration order,
  so `Map.keys/1` returns hash order and silently swaps multi-parameter calls.

  `param_order` lists every declared positional param, including those with
  defaults. A consumer that omits an optional argument must dispatch on the
  function's lower arity rather than blindly mapping all of `param_order` — the
  defaulted tail can be dropped from the right.

  """

  use Descripex.Discoverable, modules: [Descripex.Manifest, Descripex.Describe, Descripex.MCP]

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
    opts = preprocess_schemas(opts)

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

    # Propagate @doc hints: to ALL arities of each declared function.
    # The api() macro sets @doc hints: which is consumed by the next def (min arity).
    # For multi-arity functions, higher arities miss the hints in the BEAM docs chunk.
    # This directly updates the compiler's internal doc entries before the chunk is assembled.
    propagate_hints_to_all_arities(env.module, declarations, defs)

    # Build entries at compile time (without specs — can't access own specs yet)
    api_entries =
      Enum.map(declarations, fn {name, description, opts} ->
        {arity, defaults} = find_arity_and_defaults(name, defs)

        %{
          name: name,
          arity: arity,
          defaults: defaults,
          param_order: build_param_order(opts),
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
      entry
      |> Map.put(:spec, format_spec(entry.name, entry.arity, specs))
      |> fill_param_schemas_from_spec(specs)
      |> fill_opt_schemas_from_type()
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

  # --- Schema preprocessing (macro-time) ---

  # Walks opts keyword list AST, converting schema: type expressions to JSON Schema maps.
  # Must run in the macro body (before quote) where type ASTs like {:float, [], []} are available.
  # After conversion, schema values are Macro.escape'd maps that evaluate inside quote blocks.
  @doc false
  defp preprocess_schemas(opts) do
    opts
    |> maybe_convert_param_schemas(:params)
    |> maybe_convert_param_schemas(:opts)
    |> maybe_convert_returns_schema()
  end

  @doc false
  defp maybe_convert_param_schemas(opts, key) do
    case Keyword.get(opts, key) do
      nil -> opts
      [] -> opts
      params -> Keyword.put(opts, key, Enum.map(params, &convert_param_schema/1))
    end
  end

  # Converts a single param's schema: AST to a JSON Schema map via JSONSpec.convert/1
  @doc false
  defp convert_param_schema({name, details}) do
    case Keyword.get(details, :schema) do
      nil ->
        {name, details}

      schema_ast ->
        json_schema = JSONSpec.convert(schema_ast)
        {name, Keyword.put(details, :schema, Macro.escape(json_schema))}
    end
  end

  # Converts schema: AST inside a returns: map literal to JSON Schema.
  # Map literals at macro time are AST: {:%{}, meta, pairs} where pairs is a keyword list.
  @doc false
  defp maybe_convert_returns_schema(opts) do
    case Keyword.get(opts, :returns) do
      {:%{}, meta, pairs} when is_list(pairs) ->
        case Keyword.get(pairs, :schema) do
          nil ->
            opts

          schema_ast ->
            json_schema = JSONSpec.convert(schema_ast)
            new_pairs = Keyword.put(pairs, :schema, Macro.escape(json_schema))
            Keyword.put(opts, :returns, {:%{}, meta, new_pairs})
        end

      _other ->
        opts
    end
  end

  # --- Hints map ---

  @doc false
  # Positional parameter names in declaration order (the `params:` keyword list
  # is ordered). This is the authoritative source for mapping named MCP/JSON
  # arguments back onto a positional `apply(module, fun, args)` call — unlike
  # `hints[:params]`, which is a map and discards order. Includes defaulted params.
  defp build_param_order(opts) do
    opts |> Keyword.get(:params, []) |> Keyword.keys()
  end

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

  @doc false
  # Fills `hints.params.<name>.schema` for kind:value params that lack an explicit
  # typespec-derived schema, sourcing the type from the function's own @spec.
  # Positional params map 1:1 to spec argument positions via param_order. Types
  # json_spec can't express (term/any, remote types, tuples) leave the param
  # unschema'd — honest, rather than a guessed shape.
  @spec fill_param_schemas_from_spec(map(), map()) :: map()
  defp fill_param_schemas_from_spec(%{hints: %{params: params}, param_order: order} = entry, specs)
       when is_map(params) and is_list(order) do
    arg_asts = spec_arg_asts(entry.name, entry.arity, specs)

    new_params =
      order
      |> Enum.with_index()
      |> Enum.reduce(params, fn {pname, idx}, acc ->
        with details when is_map(details) <- Map.get(acc, pname),
             false <- Map.has_key?(details, :schema),
             ast when not is_nil(ast) <- Enum.at(arg_asts, idx),
             {:ok, schema} <- safe_convert(ast) do
          Map.put(acc, pname, Map.put(details, :schema, schema))
        else
          _ -> acc
        end
      end)

    put_in(entry, [:hints, :params], new_params)
  end

  defp fill_param_schemas_from_spec(entry, _specs), do: entry

  @doc false
  # Fills `hints.opts.<name>.schema` for opts that lack an explicit schema:, using
  # the declared `type:` atom as the source (opts live inside the function's final
  # keyword arg, so @spec carries no per-opt type to infer from — unlike params).
  # Reuses the same JSONSpec.convert/safe_convert path as the params: section.
  @spec fill_opt_schemas_from_type(map()) :: map()
  defp fill_opt_schemas_from_type(%{hints: %{opts: opts}} = entry) when is_map(opts) do
    new_opts = Map.new(opts, fn {name, details} -> {name, maybe_put_opt_schema(details)} end)
    put_in(entry, [:hints, :opts], new_opts)
  end

  defp fill_opt_schemas_from_type(entry), do: entry

  @doc false
  @spec maybe_put_opt_schema(map()) :: map()
  defp maybe_put_opt_schema(details) do
    with false <- Map.has_key?(details, :schema),
         type when is_atom(type) and not is_nil(type) <- Map.get(details, :type),
         ast when not is_nil(ast) <- opt_type_to_ast(type),
         {:ok, schema} <- safe_convert(ast) do
      Map.put(details, :schema, schema)
    else
      _ -> details
    end
  end

  @doc false
  # Maps an opt's declared `type:` atom to the type AST json_spec converts. Types
  # json_spec can't express bare (:list, :list_or_map, :tuple) return nil and are
  # left unschema'd rather than emitting a guessed shape — matching the params path.
  @spec opt_type_to_ast(atom()) :: Macro.t() | nil
  defp opt_type_to_ast(:atom), do: {:atom, [], []}
  defp opt_type_to_ast(:boolean), do: {:boolean, [], []}
  defp opt_type_to_ast(:float), do: {:float, [], []}
  defp opt_type_to_ast(:integer), do: {:integer, [], []}
  defp opt_type_to_ast(:number), do: {:number, [], []}
  defp opt_type_to_ast(:pos_integer), do: {:pos_integer, [], []}
  defp opt_type_to_ast(:string), do: {:binary, [], []}
  defp opt_type_to_ast(:map), do: {:map, [], []}
  defp opt_type_to_ast(_other), do: nil

  @doc false
  # Extracts the positional argument type ASTs (Elixir quoted form) from a
  # function's first @spec clause, handling the optional `when` guard wrapper.
  @spec spec_arg_asts(atom(), arity(), map()) :: [Macro.t()]
  defp spec_arg_asts(name, arity, specs) do
    case Map.get(specs, {name, arity}) do
      [spec_ast | _] ->
        case Code.Typespec.spec_to_quoted(name, spec_ast) do
          {:"::", _, [{^name, _, args}, _ret]} when is_list(args) -> args
          {:when, _, [{:"::", _, [{^name, _, args}, _ret]}, _guards]} when is_list(args) -> args
          _ -> []
        end

      _ ->
        []
    end
  end

  @doc false
  # Converts a type AST to JSON Schema, skipping unconvertible types and the
  # constraint-free `{}` that term()/any() produce (no usable type information).
  @spec safe_convert(Macro.t()) :: {:ok, map()} | :skip
  defp safe_convert(ast) do
    schema = ast |> normalize_remote_aliases() |> JSONSpec.convert()
    if is_map(schema) and map_size(schema) > 0, do: {:ok, schema}, else: :skip
  rescue
    # JSONSpec signals "type not expressible as JSON Schema" by raising, and the
    # exact exception depends on the AST shape it can't handle: ArgumentError for
    # unsupported scalars, CaseClauseError / FunctionClauseError for compound
    # shapes its `convert`/`convert_field` clauses don't match (e.g. a map field
    # like `%{required(non_neg_integer()) => <<_::256>>}`, or a bare `<<_::N>>`
    # bitstring). All three mean the same thing here — skip the param rather than
    # crash the whole manifest/describe build, per this function's contract.
    _ in [ArgumentError, CaseClauseError, FunctionClauseError] ->
      :skip
  end

  @doc false
  # `Code.Typespec.spec_to_quoted/2` resolves remote types to bare module atoms
  # (`{{:., _, [String, :t]}, _, []}`), but json_spec matches the source alias
  # form (`{:__aliases__, _, [:String]}`). json_spec supports exactly one remote
  # type — String.t() — so rewrite just that node back into alias form.
  @spec normalize_remote_aliases(Macro.t()) :: Macro.t()
  defp normalize_remote_aliases(ast) do
    Macro.prewalk(ast, fn
      {{:., dmeta, [String, fun]}, cmeta, cargs} ->
        {{:., dmeta, [{:__aliases__, dmeta, [:String]}, fun]}, cmeta, cargs}

      other ->
        other
    end)
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

  @doc false
  # Propagates @doc hints: metadata to all arities of each api()-declared function.
  # Uses the compiler's internal ETS doc table to inject hints before the BEAM docs chunk
  # is assembled. Without this, only the first arity (immediately after api()) gets hints.
  defp propagate_hints_to_all_arities(module, declarations, defs) do
    {set, _bag} = :elixir_module.data_tables(module)

    for {name, description, opts} <- declarations,
        {^name, arity} <- defs do
      inject_hints_into_doc_entry(set, name, arity, build_hints(description, opts))
    end
  end

  @doc false
  defp inject_hints_into_doc_entry(set, name, arity, hints) do
    key = {:function, name, arity}

    case :ets.lookup(set, key) do
      [{^key, ann, line, sig, doc, meta}] ->
        :ets.insert(set, {key, ann, line, sig, doc, Map.put(meta, :hints, hints)})

      _ ->
        :ok
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

    declared_params = Keyword.get(opts, :params, [])

    if declared_params != [] do
      # Collect clauses from ALL arities to handle both defaults and true multi-arity
      all_clauses =
        Enum.flat_map(matching, fn {_, arity} ->
          {:v1, :def, _meta, clauses} = Module.get_definition(env.module, {name, arity})
          clauses
        end)

      all_clause_names = Enum.map(all_clauses, &extract_clause_param_names/1)
      declared_names = Keyword.keys(declared_params)
      validate_param_match!(env, name, declared_names, all_clause_names)
    end
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
  defp validate_param_match!(env, func_name, declared_names, all_clause_names) do
    Enum.each(Enum.with_index(declared_names), fn {declared, idx} ->
      names_at_idx =
        all_clause_names
        |> Enum.map(&Enum.at(&1, idx))
        |> Enum.reject(&is_nil/1)

      actual = Enum.find(names_at_idx, :_pattern, &(&1 != :_pattern))

      cond do
        declared in names_at_idx -> :ok
        :_pattern in names_at_idx -> :ok
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
