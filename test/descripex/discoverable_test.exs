defmodule Descripex.DiscoverableTest do
  use ExUnit.Case, async: true

  alias Descripex.Test.AnnotatedFixture
  alias Descripex.Test.PlainFixture

  # Define a test module that uses Discoverable
  defmodule TestLib do
    @moduledoc false
    use Descripex.Discoverable, modules: [AnnotatedFixture, PlainFixture]
  end

  describe "generated describe/0" do
    test "returns Level 1 overview" do
      result = TestLib.describe()

      assert length(result) == 2
      assert Enum.map(result, & &1.module) == [AnnotatedFixture, PlainFixture]
      assert hd(result).annotated? == true
    end
  end

  describe "generated describe/1" do
    test "resolves short names" do
      funcs = TestLib.describe(:annotated_fixture)

      assert length(funcs) == 2
      names = Enum.map(funcs, & &1.name)
      assert :add in names
      assert :greet in names
    end

    test "resolves full module atom" do
      funcs = TestLib.describe(AnnotatedFixture)
      assert length(funcs) == 2
    end
  end

  describe "generated describe/2" do
    test "returns Level 3 detail" do
      detail = TestLib.describe(:annotated_fixture, :add)

      assert detail.name == :add
      assert detail.arity == 2
      assert %{a: _, b: _} = detail.params
    end

    test "returns nil for nonexistent function" do
      assert TestLib.describe(:annotated_fixture, :nonexistent) == nil
    end
  end

  describe "generated __descripex_modules__/0" do
    test "returns the configured module list" do
      assert TestLib.__descripex_modules__() == [AnnotatedFixture, PlainFixture]
    end
  end

  describe "compile-time validation" do
    test "missing :modules option raises CompileError" do
      assert_raise CompileError, ~r/requires a :modules option/, fn ->
        Code.compile_string("""
        defmodule InvalidDiscoverable do
          use Descripex.Discoverable
        end
        """)
      end
    after
      :code.purge(InvalidDiscoverable)
      :code.delete(InvalidDiscoverable)
    end
  end
end
