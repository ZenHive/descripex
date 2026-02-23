defmodule Descripex.DescribeTest do
  use ExUnit.Case, async: true

  alias Descripex.Describe
  alias Descripex.Test.AnnotatedFixture
  alias Descripex.Test.GammaWalls
  alias Descripex.Test.NoDocs
  alias Descripex.Test.PlainFixture
  alias Descripex.Test.V1
  alias Descripex.Test.V2

  @modules [AnnotatedFixture, PlainFixture]

  describe "describe/1 (Level 1 — library overview)" do
    test "returns correct fields for annotated module" do
      [annotated | _] = Describe.describe(@modules)

      assert annotated.module == AnnotatedFixture
      assert annotated.short_name == :annotated_fixture
      assert annotated.namespace == "/fixture"
      assert annotated.description =~ "test fixture"
      assert annotated.function_count == 2
      assert annotated.annotated? == true
    end

    test "returns correct fields for non-Descripex module" do
      [_, plain] = Describe.describe(@modules)

      assert plain.module == PlainFixture
      assert plain.short_name == :plain_fixture
      assert plain.namespace == nil
      assert plain.description =~ "plain module"
      assert plain.function_count == 1
      assert plain.annotated? == false
    end

    test "hidden docs are excluded from function count" do
      [_, plain] = Describe.describe(@modules)

      # PlainFixture has multiply (public doc) and hidden_func (@doc false)
      # Only multiply should be counted
      assert plain.function_count == 1
    end

    test "empty module list returns empty list" do
      assert Describe.describe([]) == []
    end

    test "preserves caller ordering" do
      result = Describe.describe([PlainFixture, AnnotatedFixture])
      assert Enum.map(result, & &1.module) == [PlainFixture, AnnotatedFixture]
    end

    test "module with no docs at all" do
      [summary] = Describe.describe([NoDocs])

      assert summary.module == NoDocs
      assert summary.short_name == :no_docs
      assert summary.annotated? == false
      assert summary.description == nil
    end
  end

  describe "describe/2 (Level 2 — module functions)" do
    test "returns function list for annotated module via short name" do
      funcs = Describe.describe(@modules, :annotated_fixture)

      assert length(funcs) == 2
      names = Enum.map(funcs, & &1.name)
      assert :add in names
      assert :greet in names
    end

    test "returns function list via full module atom" do
      funcs = Describe.describe(@modules, AnnotatedFixture)

      assert length(funcs) == 2
    end

    test "each function has required fields" do
      funcs = Describe.describe(@modules, :annotated_fixture)
      add = Enum.find(funcs, &(&1.name == :add))

      assert add.arity == 2
      assert add.defaults == 0
      assert add.description == "Add two numbers."
      assert is_binary(add.spec)
      assert add.spec =~ "number()"
    end

    test "function with defaults tracked correctly" do
      funcs = Describe.describe(@modules, :annotated_fixture)
      greet = Enum.find(funcs, &(&1.name == :greet))

      assert greet.arity == 2
      assert greet.defaults == 1
    end

    test "non-Descripex module returns basic function listing" do
      funcs = Describe.describe(@modules, :plain_fixture)

      assert length(funcs) == 1
      multiply = hd(funcs)
      assert multiply.name == :multiply
      assert multiply.arity == 2
      assert multiply.description == "Multiply two numbers."
      assert is_binary(multiply.spec)
    end

    test "hidden docs are excluded" do
      funcs = Describe.describe(@modules, :plain_fixture)
      names = Enum.map(funcs, & &1.name)

      refute :hidden_func in names
    end

    test "module with no @doc still lists public functions" do
      funcs = Describe.describe([NoDocs], :no_docs)

      # compute/1 has no @doc but is public — still listed (only @doc false is hidden)
      assert length(funcs) == 1
      assert hd(funcs).name == :compute
      assert hd(funcs).description == nil
    end
  end

  describe "describe/3 (Level 3 — function detail)" do
    test "returns full detail with unwrapped hints" do
      detail = Describe.describe(@modules, :annotated_fixture, :add)

      assert detail.name == :add
      assert detail.arity == 2
      assert detail.defaults == 0
      assert detail.description == "Add two numbers."
      assert is_binary(detail.spec)
      assert %{a: %{kind: :value}, b: %{kind: :value}} = detail.params
      assert detail.returns == %{type: :number, description: "Sum of a and b"}
      assert detail.opts == nil
      assert detail.errors == nil
    end

    test "returns nil for nonexistent function" do
      assert Describe.describe(@modules, :annotated_fixture, :nonexistent) == nil
    end

    test "works via short name resolution" do
      detail = Describe.describe(@modules, :annotated_fixture, :greet)

      assert detail.name == :greet
      assert detail.defaults == 1
      assert %{name: %{kind: :value}} = detail.params
    end

    test "non-Descripex module returns basic detail without hints" do
      detail = Describe.describe(@modules, :plain_fixture, :multiply)

      assert detail.name == :multiply
      assert detail.arity == 2
      assert detail.description == "Multiply two numbers."
      assert is_binary(detail.spec)
      assert detail.params == nil
      assert detail.opts == nil
      assert detail.returns == nil
      assert detail.errors == nil
    end

    test "non-Descripex module returns nil for nonexistent function" do
      assert Describe.describe(@modules, :plain_fixture, :nonexistent) == nil
    end
  end

  describe "short name resolution" do
    test "full module atom in list resolves directly" do
      funcs = Describe.describe(@modules, AnnotatedFixture)
      assert length(funcs) == 2
    end

    test "unknown short name raises ArgumentError" do
      assert_raise ArgumentError, ~r/no module found for short name :unknown/, fn ->
        Describe.describe(@modules, :unknown)
      end
    end

    test "error message lists available modules" do
      assert_raise ArgumentError, ~r/Available:.*annotated_fixture/, fn ->
        Describe.describe(@modules, :unknown)
      end
    end

    test "ambiguous short name raises ArgumentError" do
      modules = [V1.Funding, V2.Funding]

      assert_raise ArgumentError, ~r/ambiguous short name :funding/, fn ->
        Describe.describe(modules, :funding)
      end
    end

    test "ambiguous error lists matching candidates" do
      modules = [V1.Funding, V2.Funding]

      assert_raise ArgumentError, ~r/V1.Funding/, fn ->
        Describe.describe(modules, :funding)
      end
    end

    test "full module atom resolves even when short name is ambiguous" do
      modules = [V1.Funding, V2.Funding]

      funcs = Describe.describe(modules, V1.Funding)
      assert length(funcs) == 1
      assert hd(funcs).name == :rate
    end

    test "multi-word CamelCase module resolves to underscored short name" do
      # Regression: String.to_existing_atom would fail here because :gamma_walls
      # was never interned — only :GammaWalls exists as an atom from the module name
      [summary] = Describe.describe([GammaWalls])
      assert summary.short_name == :gamma_walls

      funcs = Describe.describe([GammaWalls], :gamma_walls)
      assert length(funcs) == 1
    end
  end
end
