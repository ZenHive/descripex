defmodule Descripex.Manifest do
  @moduledoc """
  Introspects modules to build a JSON-serializable API manifest.

  Combines `Code.fetch_docs/1` and type spec introspection to assemble
  a complete description of every public function — docs, hints, specs, and
  signatures — suitable for agent discovery, validators, and API generation.

  ## Usage

      manifest = Descripex.Manifest.build([MyLib.Funding, MyLib.Risk])
      manifest.modules |> hd() |> Map.get(:functions) |> hd()
      # => %{name: "annualize", arity: 2, spec: "annualize(...) :: float()", ...}

  """

  use Descripex

  api(:build, "Build a complete API manifest from the given modules.",
    params: [modules: [kind: :value, description: "List of module atoms to introspect"]],
    returns: %{type: :map, description: "JSON-serializable manifest with version, generated_at, and modules keys"},
    returns_example: %{version: "1.0", generated_at: "2025-01-01T00:00:00Z", modules: []}
  )

  @spec build([module()]) :: map()
  def build(modules) when is_list(modules) do
    %{
      version: "1.0",
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      modules: Enum.map(modules, &build_module/1)
    }
  end

  # --- Private helpers ---

  @doc false
  defp build_module(module) do
    Code.ensure_loaded!(module)

    {moduledoc_text, moduledoc_meta} = extract_moduledoc(module)
    func_docs = extract_func_docs(module)
    specs = extract_specs(module)
    api_hints = extract_api_hints(module)

    %{
      module: inspect(module),
      namespace: moduledoc_meta[:namespace],
      description: moduledoc_text,
      functions: build_functions(func_docs, specs, api_hints)
    }
  end

  @doc false
  defp extract_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, moduledoc, moduledoc_meta, _} ->
        text =
          case moduledoc do
            %{"en" => text} -> text
            _ -> nil
          end

        {text, moduledoc_meta}

      _ ->
        {nil, %{}}
    end
  end

  @doc false
  defp extract_func_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.filter(docs, fn
          {{:function, _, _}, _, _, _, _} -> true
          _ -> false
        end)

      _ ->
        []
    end
  end

  @doc false
  defp extract_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> Map.new(specs)
      _ -> %{}
    end
  end

  @doc false
  # Builds a lookup map of %{func_name_atom => hints} from __api__/0 when available.
  # This is the authoritative source for hints, ensuring all arities of a multi-arity
  # function get hints (not just the first arity where @doc hints: lands).
  defp extract_api_hints(module) do
    if function_exported?(module, :__api__, 0) do
      Map.new(module.__api__(), fn entry -> {entry.name, entry.hints} end)
    else
      %{}
    end
  end

  @doc false
  defp build_functions(func_docs, specs, api_hints) do
    func_docs
    |> Enum.reject(fn {_, _, _, doc, _} -> doc == :hidden end)
    |> Enum.map(fn {{:function, name, arity}, _line, signatures, doc, metadata} ->
      spec_str = format_spec(name, arity, specs)

      hints =
        api_hints
        |> Map.get(name, Map.get(metadata, :hints, %{}))
        |> normalize_hints()

      %{
        name: Atom.to_string(name),
        arity: arity,
        defaults: Map.get(metadata, :defaults, 0),
        signature: List.first(signatures),
        description: extract_doc_text(doc),
        spec: spec_str,
        hints: hints
      }
    end)
  end

  # Normalizes hints for JSON serialization — converts atom/tuple errors to maps
  defp normalize_hints(hints) when hints == %{}, do: %{}

  defp normalize_hints(hints) do
    case Map.get(hints, :errors) do
      nil -> hints
      errors -> Map.put(hints, :errors, Enum.map(errors, &normalize_error/1))
    end
  end

  defp normalize_error(name) when is_atom(name), do: %{name: Atom.to_string(name)}

  defp normalize_error({name, description}) when is_atom(name) and is_binary(description),
    do: %{name: Atom.to_string(name), description: description}

  defp normalize_error(%{} = map), do: map

  @doc false
  defp extract_doc_text(%{"en" => text}), do: String.trim(text)
  defp extract_doc_text(_), do: nil

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
