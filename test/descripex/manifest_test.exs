defmodule Descripex.ManifestTest do
  use ExUnit.Case, async: true

  alias Descripex.Test.AnnotatedFixture
  alias Descripex.Test.ErrorsFixture
  alias Descripex.Test.PlainFixture

  describe "build/1 with annotated module" do
    setup do
      {:ok, manifest: Descripex.Manifest.build([AnnotatedFixture])}
    end

    test "returns valid top-level structure", %{manifest: manifest} do
      assert manifest.version == "1.0"
      assert is_binary(manifest.generated_at)
      assert is_list(manifest.modules)
      assert length(manifest.modules) == 1
    end

    test "module has namespace and description", %{manifest: manifest} do
      mod = hd(manifest.modules)
      assert mod.namespace == "/fixture"
      assert mod.description =~ "test fixture"
    end

    test "functions have hints from api() declarations", %{manifest: manifest} do
      mod = hd(manifest.modules)
      add = Enum.find(mod.functions, &(&1.name == "add"))

      assert add.arity == 2
      assert add.hints.description == "Add two numbers."
      assert add.hints.params.a.kind == :value
      assert add.hints.params.b.kind == :value
      assert add.hints.returns.type == :number
    end

    test "functions have specs", %{manifest: manifest} do
      mod = hd(manifest.modules)
      add = Enum.find(mod.functions, &(&1.name == "add"))

      assert is_binary(add.spec)
      assert add.spec =~ "number()"
    end

    test "function with defaults tracked correctly", %{manifest: manifest} do
      mod = hd(manifest.modules)
      greet = Enum.find(mod.functions, &(&1.name == "greet"))

      assert greet.arity == 2
      assert greet.defaults == 1
    end

    test "each function entry has required keys", %{manifest: manifest} do
      for mod <- manifest.modules, func <- mod.functions do
        assert is_binary(func.name), "name should be string: #{inspect(func)}"
        assert is_integer(func.arity)
        assert is_integer(func.defaults)
        assert Map.has_key?(func, :signature)
        assert Map.has_key?(func, :description)
        assert Map.has_key?(func, :spec)
        assert Map.has_key?(func, :hints)
      end
    end
  end

  describe "build/1 with unannotated module" do
    setup do
      {:ok, manifest: Descripex.Manifest.build([PlainFixture])}
    end

    test "has nil namespace", %{manifest: manifest} do
      mod = hd(manifest.modules)
      assert is_nil(mod.namespace)
    end

    test "functions have empty hints", %{manifest: manifest} do
      mod = hd(manifest.modules)

      for func <- mod.functions do
        assert func.hints == %{},
               "#{func.name} should have empty hints (unannotated)"
      end
    end

    test "functions still have specs", %{manifest: manifest} do
      mod = hd(manifest.modules)
      multiply = Enum.find(mod.functions, &(&1.name == "multiply"))
      assert is_binary(multiply.spec)
    end
  end

  describe "build/1 dogfooding (self-describing)" do
    test "Manifest module has hints on build/1" do
      manifest = Descripex.Manifest.build([Descripex.Manifest])
      mod = hd(manifest.modules)
      build = Enum.find(mod.functions, &(&1.name == "build"))

      assert build.arity == 1
      assert build.hints.description =~ "Build a complete API manifest"
      assert build.hints.params.modules.kind == :value
      assert build.hints.returns.type == :map
    end

    test "Describe module has hints on describe/1" do
      manifest = Descripex.Manifest.build([Descripex.Describe])
      mod = hd(manifest.modules)
      describe_fn = Enum.find(mod.functions, &(&1.name == "describe"))

      assert describe_fn.arity == 1
      assert describe_fn.hints.description =~ "Progressive disclosure"
      assert describe_fn.hints.params.modules.kind == :value
    end
  end

  describe "build/1 multi-arity hints propagation" do
    test "all arities of a true multi-arity function have hints" do
      manifest = Descripex.Manifest.build([Descripex.Test.MultiArityFixture])
      mod = hd(manifest.modules)

      greets = Enum.filter(mod.functions, &(&1.name == "greet"))
      assert length(greets) == 2

      for func <- greets do
        assert func.hints != %{},
               "greet/#{func.arity} should have hints but got empty map"

        assert func.hints.description == "Say hello."
        assert func.hints.params.name.kind == :value
        assert func.hints.returns.type == :string
      end
    end

    test "Describe module has hints on all arities in manifest" do
      manifest = Descripex.Manifest.build([Descripex.Describe])
      mod = hd(manifest.modules)

      describes = Enum.filter(mod.functions, &(&1.name == "describe"))
      assert length(describes) == 3

      for func <- describes do
        assert func.hints != %{},
               "describe/#{func.arity} should have hints but got empty map"

        assert func.hints.description =~ "Progressive disclosure"
        assert func.hints.params.modules.kind == :value
      end
    end
  end

  describe "build/1 JSON serialization safety" do
    setup do
      {:ok, manifest: Descripex.Manifest.build([ErrorsFixture])}
    end

    test "errors with tuples are normalized to maps", %{manifest: manifest} do
      mod = hd(manifest.modules)
      verify = Enum.find(mod.functions, &(&1.name == "verify"))

      assert [timeout, invalid, failed] = verify.hints.errors
      assert timeout == %{name: "timeout"}
      assert invalid == %{name: "invalid_payload", description: "Missing required field"}
      assert failed == %{name: "verification_failed", description: "API call failed"}
    end

    test "full manifest is Jason.encode!/1 safe", %{manifest: manifest} do
      assert {:ok, json} = Jason.encode(manifest)
      assert is_binary(json)
    end

    test "mixed modules manifest is Jason.encode!/1 safe" do
      manifest =
        Descripex.Manifest.build([
          ErrorsFixture,
          AnnotatedFixture,
          PlainFixture
        ])

      assert {:ok, json} = Jason.encode(manifest)
      assert is_binary(json)
    end
  end

  describe "build/1 with schema annotations" do
    alias Descripex.Test.SchemaFixture

    setup do
      {:ok, manifest: Descripex.Manifest.build([SchemaFixture])}
    end

    test "params with schema: have JSON Schema in hints", %{manifest: manifest} do
      mod = hd(manifest.modules)
      calc = Enum.find(mod.functions, &(&1.name == "calculate"))

      assert calc.hints.params.value.schema == %{"type" => "number"}
      assert calc.hints.params.count.schema == %{"type" => "integer", "minimum" => 1}
    end

    test "opts with schema: have JSON Schema in hints", %{manifest: manifest} do
      mod = hd(manifest.modules)
      calc = Enum.find(mod.functions, &(&1.name == "calculate"))

      assert calc.hints.opts.mode.schema == %{
               "type" => "string",
               "enum" => ["normal", "fast", "precise"]
             }
    end

    test "schema manifest is JSON-serializable", %{manifest: manifest} do
      assert {:ok, json} = Jason.encode(manifest)
      assert is_binary(json)
      assert json =~ "\"schema\""
    end
  end

  describe "build/1 with mixed modules" do
    test "handles annotated and unannotated modules together" do
      manifest = Descripex.Manifest.build([AnnotatedFixture, PlainFixture])

      assert length(manifest.modules) == 2

      annotated = Enum.find(manifest.modules, &(&1.namespace == "/fixture"))
      plain = Enum.find(manifest.modules, &is_nil(&1.namespace))

      assert annotated
      assert plain

      # Annotated has hints
      add = Enum.find(annotated.functions, &(&1.name == "add"))
      assert add.hints != %{}

      # Plain has empty hints
      multiply = Enum.find(plain.functions, &(&1.name == "multiply"))
      assert multiply.hints == %{}
    end
  end
end
