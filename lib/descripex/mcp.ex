defmodule Descripex.MCP do
  @moduledoc """
  Converts Descripex-annotated modules into MCP tool definitions.

  Each `api()`-annotated function becomes an MCP tool with `name`, `description`,
  and `inputSchema` (JSON Schema). Functions without `api()` annotations are skipped.

  ## Usage

      tools = Descripex.MCP.tools([MyLib.Funding, MyLib.Risk])
      # => [%{name: "funding__annualize", description: "...", inputSchema: %{...}}, ...]

  Tool names use the module's short name (last segment, underscored) joined to
  the function name with a double underscore. Use `name_style: :full` for
  fully-qualified names.

      Descripex.MCP.tools([MyLib.Funding], name_style: :full)
      # => [%{name: "my_lib_funding__annualize", ...}]

  """

  use Descripex

  api(:tools, "Convert Descripex-annotated modules into MCP tool definitions.",
    params: [
      modules: [kind: :value, description: "List of module atoms to convert"],
      opts: [kind: :value, default: [], description: "Options: name_style (:short | :full)"]
    ],
    returns: %{type: :list, description: "List of MCP tool definition maps with name, description, and inputSchema"},
    returns_example: [
      %{
        name: "funding__annualize",
        description: "Annualize a per-period funding rate.",
        inputSchema: %{type: "object", properties: %{}, required: []}
      }
    ]
  )

  @spec tools([module()]) :: [map()]
  @spec tools([module()], keyword()) :: [map()]
  def tools(modules, opts \\ []) when is_list(modules) do
    name_style = Keyword.get(opts, :name_style, :short)

    Enum.flat_map(modules, fn module ->
      build_module_tools(module, name_style)
    end)
  end

  # Builds tool definitions for all api()-annotated functions in a module
  defp build_module_tools(module, name_style) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :__api__, 0) do
      module_prefix = module_name(module, name_style)

      Enum.map(module.__api__(), fn entry -> build_tool(entry, module_prefix) end)
    else
      []
    end
  end

  # Converts one __api__ entry into an MCP tool definition map
  defp build_tool(entry, module_prefix) do
    hints = entry.hints

    %{
      name: "#{module_prefix}__#{entry.name}",
      description: hints[:description] || Atom.to_string(entry.name),
      inputSchema: build_input_schema(hints)
    }
  end

  # Assembles a JSON Schema inputSchema from hints params and opts
  defp build_input_schema(hints) do
    {properties, required} = build_params_properties(Map.get(hints, :params, %{}))
    {opt_properties, _} = build_opts_properties(Map.get(hints, :opts, %{}))

    %{
      type: "object",
      properties: Map.merge(properties, opt_properties),
      required: required
    }
  end

  # Builds JSON Schema properties and required list from params hints
  defp build_params_properties(params) when map_size(params) == 0, do: {%{}, []}

  defp build_params_properties(params) do
    params
    |> Enum.reduce({%{}, []}, fn {name, details}, {props, req} ->
      prop = build_property(details)
      name_str = Atom.to_string(name)

      required =
        if Map.has_key?(details, :default) do
          req
        else
          [name_str | req]
        end

      {Map.put(props, name, prop), required}
    end)
    |> then(fn {props, req} -> {props, Enum.reverse(req)} end)
  end

  # Builds JSON Schema properties from opts hints (never required)
  defp build_opts_properties(opts) when map_size(opts) == 0, do: {%{}, []}

  defp build_opts_properties(opts) do
    props =
      Map.new(opts, fn {name, details} ->
        {name, build_property(details)}
      end)

    {props, []}
  end

  # Converts a single param/opt hint to a JSON Schema property.
  # If schema: is present, merges description into it.
  # Otherwise, returns description-only property.
  defp build_property(details) do
    base =
      case Map.get(details, :schema) do
        nil -> %{}
        schema when is_map(schema) -> schema
      end

    case Map.get(details, :description) do
      nil -> base
      desc -> Map.put(base, "description", desc)
    end
  end

  # Derives a snake_case module name prefix for tool naming
  defp module_name(module, :short) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp module_name(module, :full) do
    module
    |> Module.split()
    |> Enum.join("_")
    |> Macro.underscore()
  end
end
