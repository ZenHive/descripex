defmodule Mix.Tasks.Descripex.ManifestTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Descripex.Manifest

  @output_dir System.tmp_dir!()

  setup do
    output = Path.join(@output_dir, "test_manifest_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(output) end)
    {:ok, output: output}
  end

  describe "run/1 with explicit modules" do
    test "writes manifest JSON to the specified output path", %{output: output} do
      Manifest.run([
        "Descripex.Manifest",
        "--output",
        output
      ])

      assert File.exists?(output)
      manifest = output |> File.read!() |> Jason.decode!()
      assert manifest["version"] == "1.0"
      assert is_binary(manifest["generated_at"])
      assert length(manifest["modules"]) == 1
    end

    test "writes multiple modules", %{output: output} do
      Manifest.run([
        "Descripex.Manifest",
        "Descripex.Describe",
        "--output",
        output
      ])

      manifest = output |> File.read!() |> Jason.decode!()
      assert length(manifest["modules"]) == 2

      names = Enum.map(manifest["modules"], & &1["module"])
      assert "Descripex.Manifest" in names
      assert "Descripex.Describe" in names
    end

    test "--pretty produces indented JSON", %{output: output} do
      Manifest.run([
        "Descripex.Manifest",
        "--pretty",
        "--output",
        output
      ])

      json = File.read!(output)
      assert json =~ "\n"
      assert json =~ "  "
      assert {:ok, _} = Jason.decode(json)
    end

    test "compact JSON by default (no --pretty)", %{output: output} do
      Manifest.run([
        "Descripex.Manifest",
        "--output",
        output
      ])

      json = File.read!(output)
      lines = String.split(json, "\n", trim: true)
      assert length(lines) == 1
    end
  end

  describe "run/1 with --app flag" do
    test "discovers annotated modules in the :descripex app", %{output: output} do
      Manifest.run([
        "--app",
        "descripex",
        "--output",
        output
      ])

      manifest = output |> File.read!() |> Jason.decode!()
      assert manifest["modules"] != []

      module_names = Enum.map(manifest["modules"], & &1["module"])
      assert "Descripex.Manifest" in module_names
      assert "Descripex.Describe" in module_names
    end

    test "raises with clear message for unknown app name", %{output: output} do
      assert_raise Mix.Error, ~r/Unknown application :nonexistent_app_xyz/, fn ->
        Manifest.run([
          "--app",
          "nonexistent_app_xyz",
          "--output",
          output
        ])
      end
    end

    test "raises when app has no annotated modules", %{output: output} do
      assert_raise Mix.Error, ~r/No Descripex-annotated modules found/, fn ->
        Manifest.run([
          "--app",
          "logger",
          "--output",
          output
        ])
      end
    end
  end

  describe "run/1 with config fallback" do
    test "reads from :descripex, :manifest_modules config", %{output: output} do
      Application.put_env(:descripex, :manifest_modules, [Descripex.Manifest])

      on_exit(fn -> Application.delete_env(:descripex, :manifest_modules) end)

      Manifest.run(["--output", output])

      manifest = output |> File.read!() |> Jason.decode!()
      assert length(manifest["modules"]) == 1
      assert hd(manifest["modules"])["module"] == "Descripex.Manifest"
    end
  end

  describe "run/1 error cases" do
    test "raises when no modules specified and no config" do
      Application.delete_env(:descripex, :manifest_modules)

      assert_raise Mix.Error, ~r/No modules specified/, fn ->
        Manifest.run(["--output", "/dev/null"])
      end
    end
  end

  describe "run/1 output alias" do
    test "-o works as alias for --output", %{output: output} do
      Manifest.run([
        "Descripex.Manifest",
        "-o",
        output
      ])

      assert File.exists?(output)
      assert {:ok, _} = output |> File.read!() |> Jason.decode()
    end
  end
end
