defmodule Descripex.Describe do
  @moduledoc """
  Progressive disclosure for Descripex-powered libraries.

  Three levels of detail, each driven by a single `describe` function:

      describe(modules)                         # Level 1: library overview
      describe(modules, mod_or_short)           # Level 2: module functions
      describe(modules, mod_or_short, func)     # Level 3: function detail

  The first argument is always the module list. The second accepts either a full
  module atom (`MyLib.Funding`) or a short name (`:funding`). Short names are
  derived from the last segment of the module name, downcased and underscored.

  ## Examples

      modules = [MyLib.Funding, MyLib.Risk]

      Descripex.Describe.describe(modules)
      # => [%{module: MyLib.Funding, short_name: :funding, ...}, ...]

      Descripex.Describe.describe(modules, :funding)
      # => [%{name: :annualize, arity: 2, ...}, ...]

      Descripex.Describe.describe(modules, :funding, :annualize)
      # => %{name: :annualize, arity: 2, params: %{...}, ...}

  """

  use Descripex

  # --- Level 1: Library overview ---

  api(:describe, "Progressive disclosure — call with 1, 2, or 3 args for increasing detail.",
    params: [
      modules: [kind: :value, description: "List of module atoms to introspect"],
      mod_or_short: [kind: :value, description: "Full module atom or short name atom to drill into"],
      func_name: [kind: :value, description: "Function name atom for Level 3 detail"]
    ],
    returns: %{
      type: :list_or_map,
      description: "Level 1: [module_summary], Level 2: [function_summary], Level 3: function_detail | nil"
    },
    errors: [argument_error: "Raised when short name is not found or is ambiguous"]
  )

  @spec describe([module()]) :: [map()]
  def describe(modules) when is_list(modules) do
    Enum.map(modules, &module_summary/1)
  end

  # --- Level 2: Module functions ---

  @doc """
  Return the function list for a specific module.

  The second argument can be a full module atom or a short name atom.
  Raises `ArgumentError` if the short name is not found or is ambiguous.
  """
  @spec describe([module()], module() | atom()) :: [map()]
  def describe(modules, mod_or_short) when is_list(modules) and is_atom(mod_or_short) do
    module = resolve_module(modules, mod_or_short)
    module_functions(module)
  end

  # --- Level 3: Function detail ---

  @doc """
  Return full detail for a specific function in a module.

  Returns `nil` if the function is not found in the module.
  """
  @spec describe([module()], module() | atom(), atom()) :: map() | nil
  def describe(modules, mod_or_short, func_name) when is_list(modules) and is_atom(mod_or_short) and is_atom(func_name) do
    module = resolve_module(modules, mod_or_short)
    function_detail(module, func_name)
  end

  # --- Level 1 helpers ---

  @doc false
  defp module_summary(module) do
    Code.ensure_loaded!(module)
    annotated? = function_exported?(module, :__api__, 0)
    {description, _meta, namespace} = extract_moduledoc(module)

    function_count =
      if annotated? do
        length(module.__api__())
      else
        module |> extract_public_func_docs() |> length()
      end

    %{
      module: module,
      short_name: short_name(module),
      namespace: namespace,
      description: description,
      function_count: function_count,
      annotated?: annotated?
    }
  end

  # --- Level 2 helpers ---

  @doc false
  defp module_functions(module) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :__api__, 0) do
      Enum.map(module.__api__(), fn entry ->
        %{
          name: entry.name,
          arity: entry.arity,
          defaults: entry.defaults,
          description: entry.hints[:description],
          spec: entry[:spec]
        }
      end)
    else
      specs = extract_specs(module)

      module
      |> extract_public_func_docs()
      |> Enum.map(fn {{:function, name, arity}, _line, _sigs, doc, _meta} ->
        %{
          name: name,
          arity: arity,
          defaults: 0,
          description: extract_doc_text(doc),
          spec: format_spec(name, arity, specs)
        }
      end)
    end
  end

  # --- Level 3 helpers ---

  @doc false
  defp function_detail(module, func_name) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :__api__, 0) do
      case module.__api__(func_name) do
        nil ->
          nil

        entry ->
          hints = entry.hints

          %{
            name: entry.name,
            arity: entry.arity,
            defaults: entry.defaults,
            description: hints[:description],
            spec: entry[:spec],
            params: hints[:params],
            opts: hints[:opts],
            returns: hints[:returns],
            returns_example: hints[:returns_example],
            errors: hints[:errors],
            composes_with: hints[:composes_with]
          }
      end
    else
      func_doc = find_func_doc(module, func_name)

      case func_doc do
        nil ->
          nil

        {{:function, name, arity}, _line, _sigs, doc, _meta} ->
          specs = extract_specs(module)

          %{
            name: name,
            arity: arity,
            defaults: 0,
            description: extract_doc_text(doc),
            spec: format_spec(name, arity, specs),
            params: nil,
            opts: nil,
            returns: nil,
            returns_example: nil,
            errors: nil,
            composes_with: nil
          }
      end
    end
  end

  # --- Short name resolution ---

  @doc false
  defp resolve_module(modules, mod_or_short) do
    if mod_or_short in modules do
      mod_or_short
    else
      matches = Enum.filter(modules, fn mod -> short_name(mod) == mod_or_short end)

      case matches do
        [single] ->
          single

        [] ->
          available = Enum.map(modules, &short_name/1)

          raise ArgumentError,
                "no module found for short name #{inspect(mod_or_short)}. " <>
                  "Available: #{inspect(available)}"

        multiple ->
          raise ArgumentError,
                "ambiguous short name #{inspect(mod_or_short)} matches multiple modules: " <>
                  "#{inspect(multiple)}"
      end
    end
  end

  @doc false
  # Safe: input is always from Module.split/1 on known module atoms, never user input.
  # Must use String.to_atom/1 — the PascalCase segment (e.g., "GammaWalls") is interned,
  # but Macro.underscore/1 produces a new string (e.g., "gamma_walls") that may not be.
  defp short_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  # --- Doc extraction (duplicated from Manifest to keep strictly additive) ---

  @doc false
  defp extract_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => text}, meta, _} ->
        {text, meta, meta[:namespace]}

      {:docs_v1, _, _, _, _, meta, _} ->
        {nil, meta, meta[:namespace]}

      _ ->
        {nil, %{}, nil}
    end
  end

  @doc false
  defp extract_public_func_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.filter(docs, fn
          {{:function, _, _}, _, _, :hidden, _} -> false
          {{:function, _, _}, _, _, _, _} -> true
          _ -> false
        end)

      _ ->
        []
    end
  end

  @doc false
  defp find_func_doc(module, func_name) do
    module
    |> extract_public_func_docs()
    |> Enum.find(fn {{:function, name, _arity}, _, _, _, _} -> name == func_name end)
  end

  @doc false
  defp extract_doc_text(%{"en" => text}), do: String.trim(text)
  defp extract_doc_text(_), do: nil

  @doc false
  defp extract_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> Map.new(specs)
      _ -> %{}
    end
  end

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
end
