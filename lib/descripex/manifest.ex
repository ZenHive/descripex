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

    %{
      module: inspect(module),
      namespace: moduledoc_meta[:namespace],
      description: moduledoc_text,
      functions: build_functions(func_docs, specs)
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
  defp build_functions(func_docs, specs) do
    func_docs
    |> Enum.reject(fn {_, _, _, doc, _} -> doc == :hidden end)
    |> Enum.map(fn {{:function, name, arity}, _line, signatures, doc, metadata} ->
      spec_str = format_spec(name, arity, specs)

      %{
        name: Atom.to_string(name),
        arity: arity,
        defaults: Map.get(metadata, :defaults, 0),
        signature: List.first(signatures),
        description: extract_doc_text(doc),
        spec: spec_str,
        hints: Map.get(metadata, :hints, %{})
      }
    end)
  end

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
