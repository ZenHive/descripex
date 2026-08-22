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

  ### `__api__/0` vs the BEAM doc chunk

  `__api__/0` is the **runtime-enriched** introspection surface: it fills
  `hints.params.<name>.schema` / `hints.opts.<name>.schema` from the function's
  `@spec` and declared `type:` via `enrich_with_specs/2`. The BEAM doc chunk
  (`Code.fetch_docs/1` → `meta[:hints]`) is the **raw declared** surface — written
  at compile time, before the module can read its own specs, so it is not enriched.

  This asymmetry is intentional. The two surfaces therefore diverge on `:schema`
  for any param/opt that gains a spec-derived schema. Consumers that assert the two
  are equal (e.g. to verify each `@doc hints:` block is attached to the correctly
  named function) **must not** compare them raw — normalize both with
  `normalize_for_doc_compare/1`, which strips every `:schema` key:

      Descripex.normalize_for_doc_compare(Mod.__api__(:f).hints) ==
        Descripex.normalize_for_doc_compare(meta_hints)

  """

  use Descripex.Discoverable, modules: [Descripex.Manifest, Descripex.Describe, Descripex.MCP]

  @doc false
  defmacro __using__(opts) do
    namespace = Keyword.get(opts, :namespace)

    quote do
      import Descripex, only: [api: 2, api: 3, emit_api: 3]

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

  @doc """
  Declare an api whose `opts` is a compile-time **variable**, not a literal keyword list.

  `api/3` runs `preprocess_schemas/1` on the `opts` AST at macro-expansion time, which
  only works when `opts` is a literal keyword-list AST. Callers that build `opts` inside
  a `for`-comprehension or any other macro-time variable cannot use `api/3`. `emit_api/3`
  emits the identical `@doc`, `@doc hints:`, and accumulator entry as `api/3`, but skips
  schema preprocessing — so it accepts a variable `opts` AST.

  Compile-time validation (`__before_compile__`) still fires for `emit_api/3` declarations,
  identically to `api/3`, since both accumulate into `@descripex_api_declarations`.

  ## Schema keys are NOT preprocessed

  Because preprocessing is skipped, the caller is responsible for pre-converting any
  `schema:` keys to JSON Schema maps before passing them in. For-comprehension callers
  typically declare no `schema:` keys. If you have a **literal** `opts` keyword list
  (with or without `schema:`), use `api/3` instead — `emit_api/3` raises `ArgumentError`
  on a literal keyword-list `opts` to steer you to the macro that runs preprocessing.

  ## Example

      for {name, opts} <- compile_time_method_defs() do
        emit_api(name, "Generated declaration", opts)
      end
  """
  @spec emit_api(atom(), String.t(), Macro.t()) :: Macro.t()
  defmacro emit_api(name, description, opts) do
    if Keyword.keyword?(opts) do
      raise ArgumentError,
            "emit_api/3 received a literal keyword-list `opts` — use api/3 instead, " <>
              "which runs schema preprocessing on literal opts. emit_api/3 is for " <>
              "variable (e.g. for-comprehension) opts that the caller has pre-converted."
    end

    quote do
      @descripex_api_declarations {unquote(name), unquote(description), unquote(opts)}
      @doc Descripex.generate_doc(unquote(description), unquote(opts))
      @doc hints: Descripex.build_hints(unquote(description), unquote(opts))
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

  @doc """
  List the `kind: :value` params that ship **without** a JSON Schema, and why.

  Spec-derived schemas are best-effort: `enrich_with_specs/2` fills
  `hints.params.<name>.schema` from the function's own `@spec`, but a type json_spec
  cannot express leaves the param description-only. MCP clients then guess how to
  serialize the argument — and the guess is usually the string form of the term.
  This function makes that set queryable instead of silent, so a typeless param on
  an `api()` surface is visible before a client trips over it at runtime.

  Each entry is a map with `:module`, `:function`, `:arity`, `:param`, `:spec_type`
  (the offending type as written, or `nil` when the function declares no `@spec`)
  and `:reason`:

    * `:no_spec` — the function has no `@spec`, so there was no type to derive from.
    * `:no_type_info` — the type converts to the constraint-free `{}` (`term()`,
      `any()`). There is nothing to advertise; skipping is correct.
    * `:unconvertible` — json_spec could not express the type and no structural
      fold rescued it: tuples, bitstrings, non-`String` remote types, or a union
      whose members are themselves unconvertible. **This is the class worth acting
      on** — declare an explicit `schema:` on the param.

  Params that declare an explicit `schema:` never appear here, and neither do
  `kind: :exchange_data` params (the caller does not supply those).

      Descripex.typeless_params([MyLib.Orders, MyLib.Funding])
      #=> [
      #     %{
      #       module: MyLib.Orders,
      #       function: :store,
      #       arity: 2,
      #       param: :handle,
      #       spec_type: "{module(), keyword()}",
      #       reason: :unconvertible
      #     }
      #   ]

  A CI check can gate on the actionable class:

      assert Enum.filter(Descripex.typeless_params(mods), &(&1.reason == :unconvertible)) == []
  """
  @spec typeless_params([module()]) :: [map()]
  def typeless_params(modules) when is_list(modules) do
    Enum.flat_map(modules, &module_typeless_params/1)
  end

  @spec module_typeless_params(module()) :: [map()]
  defp module_typeless_params(module) do
    # Code.ensure_loaded?/1 before function_exported?/3: the latter answers `false`
    # for a module that simply has not been loaded yet, which under lazy loading
    # makes an annotated module look unannotated.
    if Code.ensure_loaded?(module) and function_exported?(module, :__api__, 0) do
      specs =
        case Code.Typespec.fetch_specs(module) do
          {:ok, specs} -> Map.new(specs)
          _ -> %{}
        end

      Enum.flat_map(module.__api__(), &entry_typeless_params(module, &1, specs))
    else
      []
    end
  end

  @spec entry_typeless_params(module(), map(), map()) :: [map()]
  defp entry_typeless_params(module, entry, specs) do
    params = get_in(entry, [:hints, :params]) || %{}
    order = Map.get(entry, :param_order) || []
    arg_asts = spec_arg_asts(entry.name, entry.arity, specs)

    order
    |> Enum.with_index()
    |> Enum.flat_map(fn {pname, index} ->
      params
      |> Map.get(pname)
      |> param_typeless_reason(Enum.at(arg_asts, index))
      |> Enum.map(fn {spec_type, reason} ->
        %{
          module: module,
          function: entry.name,
          arity: entry.arity,
          param: pname,
          spec_type: spec_type,
          reason: reason
        }
      end)
    end)
  end

  # Returns [] when the param is already typed (or is not a caller-supplied value),
  # or a single {spec_type, reason} pair when it ships typeless.
  @spec param_typeless_reason(map() | nil, Macro.t() | nil) :: [{String.t() | nil, atom()}]
  defp param_typeless_reason(details, ast) do
    cond do
      not is_map(details) -> []
      Map.get(details, :kind) != :value -> []
      Map.has_key?(details, :schema) -> []
      is_nil(ast) -> [{nil, :no_spec}]
      true -> classified_typeless_reason(ast)
    end
  end

  @spec classified_typeless_reason(Macro.t()) :: [{String.t(), atom()}]
  defp classified_typeless_reason(ast) do
    case classify_convert(ast) do
      {:ok, _schema} -> []
      {:skip, reason} -> [{Macro.to_string(ast), reason}]
    end
  end

  @doc """
  Strip every `:schema` key from a `hints` map so the runtime-enriched `__api__/0`
  surface can be compared for equality against the raw compile-time doc chunk
  (`Code.fetch_docs/1` → `meta[:hints]`).

  `__api__/0` fills `hints.params.<name>.schema` / `hints.opts.<name>.schema` from
  `@spec`/`type:` at runtime (see `enrich_with_specs/2`), but the doc chunk is
  written at compile time and is **not** enriched — a module can't read its own
  specs at `__before_compile__`. So the two surfaces diverge on `:schema`, and a
  consumer that asserts they are equal (e.g. to detect `api()` misattachment)
  false-positives purely on the injected schema.

  This drops **all** schema keys — author-declared and spec-injected alike, which
  are indistinguishable once merged — from `:params`, `:opts`, and `:returns`.
  Apply it to **both** surfaces before comparing:

      Descripex.normalize_for_doc_compare(Mod.__api__(:f).hints) ==
        Descripex.normalize_for_doc_compare(meta_hints)
  """
  @spec normalize_for_doc_compare(map()) :: map()
  def normalize_for_doc_compare(hints) when is_map(hints) do
    hints
    |> drop_section_schemas(:params)
    |> drop_section_schemas(:opts)
    |> drop_returns_schema()
  end

  @spec drop_section_schemas(map(), atom()) :: map()
  defp drop_section_schemas(hints, key) do
    case Map.get(hints, key) do
      section when is_map(section) ->
        Map.put(hints, key, Map.new(section, fn {name, details} -> {name, Map.delete(details, :schema)} end))

      _ ->
        hints
    end
  end

  @spec drop_returns_schema(map()) :: map()
  defp drop_returns_schema(hints) do
    case Map.get(hints, :returns) do
      returns when is_map(returns) -> Map.put(hints, :returns, Map.delete(returns, :schema))
      _ -> hints
    end
  end

  # --- Doc generation ---

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

  defp escape_alternating([], _outside?, acc), do: acc

  defp escape_alternating([segment | rest], true, acc) do
    escaped = String.replace(segment, ~r/[{}]/, "\\\\\\0")
    escape_alternating(rest, false, [escaped | acc])
  end

  defp escape_alternating([segment | rest], false, acc) do
    escape_alternating(rest, true, [segment | acc])
  end

  # Joins `lines` with "\n" and prepends `prefix`, building the result as a
  # single iolist->binary pass instead of `prefix <> Enum.join(lines, "\n")`.
  defp join_section(prefix, lines) do
    IO.iodata_to_binary([prefix | Enum.intersperse(lines, "\n")])
  end

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

    join_section("## Parameters\n\n", lines)
  end

  defp format_opts_section([]), do: nil

  defp format_opts_section(opt_params) do
    lines =
      Enum.map(opt_params, fn {name, details} ->
        desc = Keyword.get(details, :description, "")
        default = Keyword.get(details, :default)
        default_str = if default == nil, do: "", else: " (default: `#{inspect(default)}`)"
        "  * `#{name}` - #{escape_doc(desc)}#{default_str}"
      end)

    join_section("## Options\n\n", lines)
  end

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

  defp format_errors_section([]), do: nil

  defp format_errors_section(errors) do
    lines =
      Enum.map(errors, fn
        name when is_atom(name) ->
          "  * `#{inspect(name)}`"

        {name, description} ->
          "  * `#{inspect(name)}` - #{escape_doc(description)}"
      end)

    join_section("## Errors\n\n", lines)
  end

  defp format_composes_with_section([]), do: nil

  defp format_composes_with_section(composes_with) do
    lines =
      Enum.map(composes_with, fn name ->
        "  * `#{name}`"
      end)

    join_section("## Composes With\n\n", lines)
  end

  defp format_contract_block(contract) do
    contract_literal = inspect(contract, pretty: true, limit: :infinity)
    "```elixir\n# descripex:contract\n#{contract_literal}\n```"
  end

  defp format_returns_example(returns_example) do
    literal = inspect(returns_example, pretty: true, limit: :infinity)
    "### Example\n\n```elixir\n#{literal}\n```"
  end

  defp build_param_suffix(kind, default) do
    parts = []
    parts = if default == nil, do: parts, else: ["default: `#{inspect(default)}`" | parts]
    parts = if kind, do: [Atom.to_string(kind) | parts], else: parts

    case parts do
      [] -> ""
      _ -> IO.iodata_to_binary([" (", Enum.intersperse(Enum.reverse(parts), ", "), ")"])
    end
  end

  # --- Schema preprocessing (macro-time) ---

  # Walks opts keyword list AST, converting schema: type expressions to JSON Schema maps.
  # Must run in the macro body (before quote) where type ASTs like {:float, [], []} are available.
  # After conversion, schema values are Macro.escape'd maps that evaluate inside quote blocks.
  defp preprocess_schemas(opts) do
    opts
    |> maybe_convert_param_schemas(:params)
    |> maybe_convert_param_schemas(:opts)
    |> maybe_convert_returns_schema()
  end

  defp maybe_convert_param_schemas(opts, key) do
    case Keyword.get(opts, key) do
      nil -> opts
      [] -> opts
      params -> Keyword.put(opts, key, Enum.map(params, &convert_param_schema/1))
    end
  end

  # Converts a single param's schema: AST to a JSON Schema map via JSONSpec.convert/1
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

  # Positional parameter names in declaration order (the `params:` keyword list
  # is ordered). This is the authoritative source for mapping named MCP/JSON
  # arguments back onto a positional `apply(module, fun, args)` call — unlike
  # `hints[:params]`, which is a map and discards order. Includes defaulted params.
  defp build_param_order(opts) do
    opts |> Keyword.get(:params, []) |> Keyword.keys()
  end

  defp build_params_map([]), do: nil

  defp build_params_map(params) do
    Map.new(params, fn {name, details} ->
      {name, Map.new(details)}
    end)
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  # --- Spec formatting (called at runtime) ---

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
      |> Enum.zip(arg_asts)
      |> Enum.reduce(params, fn {pname, ast}, acc ->
        with details when is_map(details) <- Map.get(acc, pname),
             false <- Map.has_key?(details, :schema),
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
  # Converts a type AST to JSON Schema, skipping types with no usable JSON Schema
  # meaning. `classify_convert/1` carries the two skip reasons apart.
  @spec safe_convert(Macro.t()) :: {:ok, map()} | :skip
  defp safe_convert(ast) do
    case classify_convert(ast) do
      {:ok, schema} -> {:ok, schema}
      {:skip, _reason} -> :skip
    end
  end

  @doc false
  # Same conversion as `safe_convert/1`, but keeps WHY a type went unschema'd:
  #
  #   * `:no_type_info` — json_spec converted it to the constraint-free `{}`
  #     (`term()`/`any()`). There is genuinely nothing to advertise.
  #   * `:unconvertible` — json_spec raised and no structural fold rescued it
  #     (tuples, bitstrings, non-`String` remote types, unions whose members are
  #     themselves unconvertible).
  #
  # `typeless_params/1` surfaces the second class — the one worth acting on,
  # because the param could have shipped a type and did not.
  @spec classify_convert(Macro.t()) :: {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp classify_convert(ast), do: ast |> normalize_type_ast() |> convert_type()

  @doc false
  # Tries json_spec on the WHOLE type first. That order is load-bearing, not an
  # optimization: json_spec already converts the all-atom union (`:buy | :sell`
  # -> enum) and the nullable union (`T | nil`), and in both cases the individual
  # members raise standalone (`:buy` and `nil` are not convertible types). A
  # member-by-member fold applied first would regress both forms to typeless.
  # Only once the whole type raises do we decompose it.
  @spec convert_type(Macro.t()) :: {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp convert_type(ast) do
    case direct_convert(ast) do
      {:skip, :unconvertible} -> decompose_convert(ast)
      result -> result
    end
  end

  @doc false
  @spec direct_convert(Macro.t()) :: {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp direct_convert(ast) do
    # JSONSpec.convert/1 always returns a map (`{}` for type-info-free term()/any()),
    # so only the emptiness check is meaningful — an is_map/1 guard here is provably
    # always-true and dialyzer flags its dead `false` branch.
    schema = JSONSpec.convert(ast)
    if map_size(schema) > 0, do: {:ok, schema}, else: {:skip, :no_type_info}
  rescue
    # JSONSpec signals "type not expressible as JSON Schema" by raising, and the
    # exact exception depends on the AST shape it can't handle: ArgumentError for
    # unsupported scalars and unions, CaseClauseError / FunctionClauseError for
    # compound shapes its `convert`/`convert_field` clauses don't match (e.g. a map
    # field like `%{required(non_neg_integer()) => <<_::256>>}`, or a bare
    # `<<_::N>>` bitstring).
    _ in [ArgumentError, CaseClauseError, FunctionClauseError] ->
      {:skip, :unconvertible}
  end

  @doc false
  # Structural fallback for types json_spec rejects wholesale but that JSON Schema
  # can still express once taken apart. Only two shapes qualify; everything else
  # stays skipped rather than shipping a guessed schema.
  @spec decompose_convert(Macro.t()) :: {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp decompose_convert({:|, _meta, [_left, _right]} = ast) do
    # json_spec itself discards nullability (`String.t() | nil` yields a bare
    # string schema), so dropping `nil` members here matches upstream behaviour
    # rather than inventing one.
    ast |> union_members() |> Enum.reject(&is_nil/1) |> convert_union_members()
  end

  defp decompose_convert([elem]), do: convert_array(elem)
  defp decompose_convert({:list, _meta, [elem]}), do: convert_array(elem)
  defp decompose_convert(_other), do: {:skip, :unconvertible}

  @doc false
  # Unions nest right-associatively in the AST (`a | (b | c)`); flatten to a list.
  @spec union_members(Macro.t()) :: [Macro.t()]
  defp union_members({:|, _meta, [left, right]}), do: union_members(left) ++ union_members(right)
  defp union_members(other), do: [other]

  @doc false
  # A union json_spec rejected wholesale. Convert every remaining member: if they
  # all agree, that shared schema is exact — `atom()` and `String.t()` both convert
  # to `%{"type" => "string"}`, so folding `atom() | String.t()` is lossless because
  # the members AGREE, not because one is wider. If they differ, `anyOf` expresses
  # the union losslessly. There is no widening step and no guessing: a member that
  # cannot convert skips the whole union.
  @spec convert_union_members([Macro.t()]) ::
          {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp convert_union_members([]), do: {:skip, :unconvertible}

  defp convert_union_members(members) do
    converted = Enum.map(members, &convert_type/1)

    if Enum.all?(converted, &match?({:ok, _schema}, &1)) do
      converted |> Enum.map(fn {:ok, schema} -> schema end) |> Enum.uniq() |> union_schema()
    else
      {:skip, :unconvertible}
    end
  end

  @doc false
  # One distinct member schema means the union collapses exactly; more than one
  # means `anyOf`, which expresses it losslessly.
  @spec union_schema([map()]) :: {:ok, map()}
  defp union_schema([single]), do: {:ok, single}
  defp union_schema(many), do: {:ok, %{"anyOf" => many}}

  @doc false
  # `[T]` / `list(T)` whose ELEMENT type json_spec choked on, e.g.
  # `[atom() | String.t()]`. The list form itself is supported, so rebuild it
  # around the folded element schema.
  @spec convert_array(Macro.t()) :: {:ok, map()} | {:skip, :no_type_info | :unconvertible}
  defp convert_array(elem) do
    case convert_type(elem) do
      {:ok, items} -> {:ok, %{"type" => "array", "items" => items}}
      skip -> skip
    end
  end

  @doc false
  # Normalizes a spec-derived type AST into shapes json_spec accepts, before any
  # conversion is attempted. Two rewrites, both pure AST-to-AST:
  #
  #   * `Code.Typespec.spec_to_quoted/2` resolves remote types to bare module
  #     atoms (`{{:., _, [String, :t]}, _, []}`), but json_spec matches the source
  #     alias form (`{:__aliases__, _, [:String]}`). json_spec supports exactly one
  #     remote type — String.t() — so rewrite just that node back into alias form.
  #   * `module()` and `node()` are Elixir built-in aliases for `atom()` — an exact
  #     documented equivalence, not a widening — but json_spec knows neither name.
  #     Rewrite them to `atom()` so `[module()]` and `module() | String.t()` convert
  #     instead of shipping typeless.
  #   * json_spec supports only the `[T]` and `list(T)` list forms, so fold
  #     `nonempty_list(T)` and the `[T, ...]` literal down to `[T]`. JSON Schema
  #     has no non-empty-array keyword short of `minItems`, so the fold loses
  #     nothing json_spec was going to express. `spec_to_quoted/2` already
  #     normalizes `nonempty_list(T)` INTO `[T, ...]`, so the `nonempty_list`
  #     clause only fires on hand-written ASTs.
  #
  # Unions are deliberately NOT handled here: deciding one requires comparing
  # CONVERTED schemas, and `anyOf` has no type-AST spelling. See
  # `decompose_convert/1`.
  @spec normalize_type_ast(Macro.t()) :: Macro.t()
  defp normalize_type_ast(ast) do
    Macro.prewalk(ast, fn
      {{:., dmeta, [String, fun]}, cmeta, cargs} ->
        {{:., dmeta, [{:__aliases__, dmeta, [:String]}, fun]}, cmeta, cargs}

      {:nonempty_list, _meta, [elem]} ->
        [elem]

      {alias_type, meta, []} when alias_type in [:module, :node] ->
        {:atom, meta, []}

      [elem, {:..., _meta, _args}] ->
        [elem]

      other ->
        other
    end)
  end

  # --- Compile-time helpers ---

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

  defp validate_param_match!(env, func_name, declared_names, all_clause_names) do
    # Each clause's name list is converted to a tuple once so per-index lookups
    # below are O(1) via elem/2 instead of O(n) via repeated Enum.at/2.
    clause_tuples = Enum.map(all_clause_names, &List.to_tuple/1)

    Enum.each(Enum.with_index(declared_names), fn {declared, idx} ->
      names_at_idx =
        clause_tuples
        |> Enum.map(&tuple_at(&1, idx))
        |> Enum.reject(&is_nil/1)

      actual = Enum.find(names_at_idx, :_pattern, &(&1 != :_pattern))

      cond do
        declared in names_at_idx -> :ok
        :_pattern in names_at_idx -> :ok
        true -> raise_param_mismatch!(env, func_name, declared, idx, actual)
      end
    end)
  end

  defp tuple_at(tuple, idx) when idx < tuple_size(tuple), do: elem(tuple, idx)
  defp tuple_at(_tuple, _idx), do: nil

  defp raise_param_mismatch!(env, name, declared, idx, actual) do
    raise CompileError,
      file: env.file,
      line: 0,
      description:
        "api :#{name} param :#{declared} at position #{idx} " <>
          "doesn't match def param :#{actual}"
  end

  defp append_api_table_to_moduledoc(nil, table), do: table

  defp append_api_table_to_moduledoc({_, nil}, table), do: table
  defp append_api_table_to_moduledoc(false, _table), do: false
  defp append_api_table_to_moduledoc({_, false}, _table), do: false

  defp append_api_table_to_moduledoc({_, text}, table) when is_binary(text) do
    text <> "\n\n" <> table
  end

  defp write_moduledoc_quote(false), do: quote(do: nil)

  defp write_moduledoc_quote(text) when is_binary(text) do
    quote do
      @moduledoc unquote(text)
    end
  end

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

  defp escape_table_cell(text) do
    text
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace("\n", "<br>")
  end
end
