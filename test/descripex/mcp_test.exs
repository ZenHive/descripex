defmodule Descripex.MCPTest do
  use ExUnit.Case, async: true

  alias Descripex.Test.AnnotatedFixture
  alias Descripex.Test.ErrorsFixture
  alias Descripex.Test.MultiArityFixture
  alias Descripex.Test.PlainFixture
  alias Descripex.Test.SchemaFixture
  alias Descripex.Test.SpecTypedFixture
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

    test "explicit schema: still wins over spec-derived type" do
      tools = Descripex.MCP.tools([SchemaFixture])
      calc = Enum.find(tools, &(&1.name == "schema_fixture__calculate"))

      # value/count declared schema: float()/pos_integer() — unchanged by spec fill
      assert calc.inputSchema.properties.value["type"] == "number"
      assert calc.inputSchema.properties.count["minimum"] == 1
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
end
