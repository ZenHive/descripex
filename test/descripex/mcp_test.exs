defmodule Descripex.MCPTest do
  use ExUnit.Case, async: true

  alias Descripex.Test.AnnotatedFixture
  alias Descripex.Test.ErrorsFixture
  alias Descripex.Test.MultiArityFixture
  alias Descripex.Test.PlainFixture
  alias Descripex.Test.SchemaFixture
  alias Descripex.Test.SpecTypedFixture
  alias Descripex.Test.SpecUnionFixture
  alias Descripex.Test.V1
  alias Descripex.Test.V2

  describe "tools/1 basic" do
    test "returns tool definitions for annotated module" do
      tools = Descripex.MCP.tools([AnnotatedFixture])
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert "annotated_fixture__add" in names
      assert "annotated_fixture__greet" in names
    end

    test "each tool has name, description, and inputSchema" do
      [tool | _] = Descripex.MCP.tools([AnnotatedFixture])

      assert is_binary(tool.name)
      assert is_binary(tool.description)
      assert is_map(tool.inputSchema)
      assert tool.inputSchema.type == "object"
      assert is_map(tool.inputSchema.properties)
      assert is_list(tool.inputSchema.required)
    end

    test "returns empty list for unannotated module" do
      assert Descripex.MCP.tools([PlainFixture]) == []
    end

    test "returns empty list for empty module list" do
      assert Descripex.MCP.tools([]) == []
    end
  end

  describe "tools/1 inputSchema" do
    test "params without defaults are required" do
      tools = Descripex.MCP.tools([AnnotatedFixture])
      add = Enum.find(tools, &(&1.name == "annotated_fixture__add"))

      assert "a" in add.inputSchema.required
      assert "b" in add.inputSchema.required
    end

    test "params with defaults are not required" do
      tools = Descripex.MCP.tools([AnnotatedFixture])
      greet = Enum.find(tools, &(&1.name == "annotated_fixture__greet"))

      assert "name" in greet.inputSchema.required
      refute "prefix" in greet.inputSchema.required
    end

    test "param descriptions flow into properties" do
      tools = Descripex.MCP.tools([AnnotatedFixture])
      add = Enum.find(tools, &(&1.name == "annotated_fixture__add"))

      assert add.inputSchema.properties.a["description"] == "First number"
      assert add.inputSchema.properties.b["description"] == "Second number"
    end

    test "schema annotations produce typed JSON Schema properties" do
      tools = Descripex.MCP.tools([SchemaFixture])
      calc = Enum.find(tools, &(&1.name == "schema_fixture__calculate"))

      # Params with schema: get JSON Schema type info
      assert calc.inputSchema.properties.value["type"] == "number"
      assert calc.inputSchema.properties.count["type"] == "integer"
      assert calc.inputSchema.properties.count["minimum"] == 1
    end

    test "opts are included as optional properties" do
      tools = Descripex.MCP.tools([SchemaFixture])
      calc = Enum.find(tools, &(&1.name == "schema_fixture__calculate"))

      # mode opt is present in properties
      assert Map.has_key?(calc.inputSchema.properties, :mode)
      assert calc.inputSchema.properties.mode["enum"] == ["normal", "fast", "precise"]

      # but not required
      refute "mode" in calc.inputSchema.required
    end

    test "spec-derived types fill kind:value params lacking an explicit schema:" do
      tools = Descripex.MCP.tools([SpecTypedFixture])
      place = Enum.find(tools, &(&1.name == "spec_typed_fixture__place"))
      props = place.inputSchema.properties

      # scalar float -> number; list -> array
      assert props.price["type"] == "number"
      assert props.tags["type"] == "array"
      # atom union -> string enum
      assert props.side["type"] == "string"
      assert props.side["enum"] == ["buy", "sell"]
      # descriptions still flow through alongside the derived type
      assert props.price["description"] == "Limit price"
    end

    test "plain atom() param emits type:string" do
      tools = Descripex.MCP.tools([SpecTypedFixture])
      tag = Enum.find(tools, &(&1.name == "spec_typed_fixture__tag"))

      assert tag.inputSchema.properties.id["type"] == "integer"
      assert tag.inputSchema.properties.label["type"] == "string"
    end

    test "no kind:value param property is description-only (regression)" do
      tools = Descripex.MCP.tools([SpecTypedFixture])

      for tool <- tools, {_name, prop} <- tool.inputSchema.properties do
        assert Map.has_key?(prop, "type") or Map.has_key?(prop, "enum"),
               "property #{inspect(prop)} in #{tool.name} is typeless (description-only)"
      end
    end

    test "schema-less opts get a typed property from their declared type:" do
      tools = Descripex.MCP.tools([SpecTypedFixture])
      cfg = Enum.find(tools, &(&1.name == "spec_typed_fixture__configure"))
      props = cfg.inputSchema.properties

      assert props.limit["type"] == "integer"
      assert props.mode["type"] == "string"
      assert props.verbose["type"] == "boolean"
      # opts are never required, and descriptions still flow through
      refute "limit" in cfg.inputSchema.required
      assert props.limit["description"] == "Max records"
    end

    test "no opts property is description-only (regression)" do
      tools = Descripex.MCP.tools([SpecTypedFixture])
      cfg = Enum.find(tools, &(&1.name == "spec_typed_fixture__configure"))

      for {name, prop} <- cfg.inputSchema.properties, name in [:limit, :mode, :verbose] do
        assert Map.has_key?(prop, "type") or Map.has_key?(prop, "enum"),
               "opt #{name} property #{inspect(prop)} is typeless (description-only)"
      end
    end

    test "explicit schema: on an opt still wins over type:-derived" do
      tools = Descripex.MCP.tools([SchemaFixture])
      calc = Enum.find(tools, &(&1.name == "schema_fixture__calculate"))

      # mode declares type: :atom AND schema: enum — the explicit enum is preserved
      assert calc.inputSchema.properties.mode["enum"] == ["normal", "fast", "precise"]
    end

    test "explicit schema: still wins over spec-derived type" do
      tools = Descripex.MCP.tools([SchemaFixture])
      calc = Enum.find(tools, &(&1.name == "schema_fixture__calculate"))

      # value/count declared schema: float()/pos_integer() — unchanged by spec fill
      assert calc.inputSchema.properties.value["type"] == "number"
      assert calc.inputSchema.properties.count["minimum"] == 1
    end

    test "nonempty_list(T) and [T, ...] emit the same array schema as [T]" do
      props = union_props()

      # [String.t()] — the form json_spec already supported, unchanged
      assert props.warm_paths == %{
               "type" => "array",
               "items" => %{"type" => "string"},
               "description" => "Warm paths"
             }

      # [String.t(), ...] folds to the same shape
      assert props.tags["type"] == "array"
      assert props.tags["items"] == %{"type" => "string"}

      # nonempty_list(atom() | String.t()) — non-empty fold AND union fold
      assert props.languages["type"] == "array"
      assert props.languages["items"] == %{"type" => "string"}
    end

    test "a union whose members agree emits that shared schema" do
      # atom() and String.t() both convert to {"type": "string"} — folding is
      # lossless because the members AGREE, not because one is wider.
      assert union_props().mode["type"] == "string"
    end

    test "a union whose members differ emits anyOf rather than picking one" do
      assert union_props().ratio["anyOf"] == [%{"type" => "integer"}, %{"type" => "string"}]
    end

    test "union forms json_spec already converts keep their exact output (regression)" do
      # These two must survive the per-member fold: their MEMBERS raise standalone
      # (`:buy` and `nil` are not convertible types), so a fold applied before the
      # whole-union attempt would silently regress both to typeless.
      side =
        [SpecTypedFixture]
        |> Descripex.MCP.tools()
        |> Enum.find(&(&1.name == "spec_typed_fixture__place"))
        |> then(& &1.inputSchema.properties.side)

      assert side["type"] == "string"
      assert side["enum"] == ["buy", "sell"]

      # String.t() | nil stays a bare string schema — json_spec itself discards
      # nullability, and the fold must not turn it into anyOf.
      assert union_props().label == %{"type" => "string", "description" => "Label"}
    end

    test "these forms work as a top-level param type, not only as a list element" do
      props = union_props()

      # mode/ratio/label are bare top-level unions; languages/tags are list elements
      assert Map.has_key?(props.mode, "type")
      assert Map.has_key?(props.ratio, "anyOf")
      assert Map.has_key?(props.label, "type")
    end

    test "no register/6 property is description-only (regression)" do
      for {name, prop} <- union_props() do
        assert Map.has_key?(prop, "type") or Map.has_key?(prop, "enum") or
                 Map.has_key?(prop, "anyOf"),
               "property #{name} #{inspect(prop)} is typeless (description-only)"
      end
    end

    test "module() and node() convert as the atom() aliases they are defined as" do
      props =
        [SpecUnionFixture]
        |> Descripex.MCP.tools()
        |> Enum.find(&(&1.name == "spec_union_fixture__load"))
        |> then(& &1.inputSchema.properties)

      # Elixir defines module() :: atom() and node() :: atom(); json_spec knows
      # neither name, so without the alias fold all three ship typeless.
      assert props.modules["type"] == "array"
      assert props.modules["items"] == %{"type" => "string"}
      assert props.target["type"] == "string"
      # module() | String.t() — members agree once module() is atom()
      assert props.origin["type"] == "string"
    end

    test "genuinely inexpressible types still skip without a guessed shape" do
      store =
        [SpecUnionFixture]
        |> Descripex.MCP.tools()
        |> Enum.find(&(&1.name == "spec_union_fixture__store"))

      props = store.inputSchema.properties

      # expressible — still typed
      assert props.key["type"] == "string"

      # a tuple and term() have no honest JSON Schema; description-only is correct
      assert props.handle == %{"description" => "Opaque handle"}
      assert props.anything == %{"description" => "Anything at all"}
    end

    test "function with no params has empty inputSchema" do
      tools = Descripex.MCP.tools([Descripex.Test.GammaWalls])
      calc = Enum.find(tools, &(&1.name == "gamma_walls__calculate"))

      assert calc.inputSchema.properties == %{}
      assert calc.inputSchema.required == []
    end
  end

  describe "tools/2 name_style" do
    test "short style uses last module segment" do
      tools = Descripex.MCP.tools([V1.Funding], name_style: :short)
      assert hd(tools).name == "funding__rate"
    end

    test "full style uses all module segments" do
      tools = Descripex.MCP.tools([V1.Funding], name_style: :full)
      assert hd(tools).name == "descripex__test_v1__funding__rate"
    end

    test "distinct names for same-named modules across namespaces" do
      tools = Descripex.MCP.tools([V1.Funding, V2.Funding], name_style: :full)
      names = Enum.map(tools, & &1.name)

      assert "descripex__test_v1__funding__rate" in names
      assert "descripex__test_v2__funding__rate" in names
    end
  end

  describe "multi-module" do
    test "flattens tools from multiple modules" do
      tools = Descripex.MCP.tools([AnnotatedFixture, SchemaFixture])
      assert length(tools) == 3

      names = Enum.map(tools, & &1.name)
      assert "annotated_fixture__add" in names
      assert "annotated_fixture__greet" in names
      assert "schema_fixture__calculate" in names
    end
  end

  describe "multi-arity" do
    test "produces one tool per function (max arity)" do
      tools = Descripex.MCP.tools([MultiArityFixture])
      assert length(tools) == 1
      assert hd(tools).name == "multi_arity_fixture__greet"
    end
  end

  describe "errors fixture" do
    test "module with errors produces valid tools" do
      tools = Descripex.MCP.tools([ErrorsFixture])
      assert length(tools) == 1

      tool = hd(tools)
      assert tool.name == "errors_fixture__verify"
      assert "payload" in tool.inputSchema.required
    end
  end

  describe "JSON serialization" do
    test "tool definitions are JSON-serializable" do
      tools = Descripex.MCP.tools([AnnotatedFixture, SchemaFixture, ErrorsFixture])
      assert {:ok, json} = Jason.encode(tools)
      assert is_binary(json)
    end

    test "schema-rich tools serialize correctly" do
      tools = Descripex.MCP.tools([SchemaFixture])
      {:ok, json} = Jason.encode(tools)
      decoded = Jason.decode!(json)

      calc = hd(decoded)
      assert calc["inputSchema"]["properties"]["value"]["type"] == "number"
    end
  end

  defp union_props do
    [SpecUnionFixture]
    |> Descripex.MCP.tools()
    |> Enum.find(&(&1.name == "spec_union_fixture__register"))
    |> then(& &1.inputSchema.properties)
  end
end
