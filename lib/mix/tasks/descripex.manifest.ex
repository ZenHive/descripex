defmodule Mix.Tasks.Descripex.Manifest do
  @shortdoc "Export a JSON manifest of Descripex-annotated modules"

  @moduledoc """
  Writes a JSON manifest of Descripex-annotated modules to a file.

  The manifest is produced by `Descripex.Manifest.build/1` and contains
  version, timestamp, and full function metadata (docs, hints, specs,
  signatures) for every public function in the given modules.

  ## Usage

      # Explicit module list
      mix descripex.manifest MyApp.Funding MyApp.Risk

      # Auto-discover annotated modules in an application
      mix descripex.manifest --app my_app

      # Custom output path
      mix descripex.manifest --output priv/manifest.json MyApp.Funding

      # Pretty-printed JSON
      mix descripex.manifest --pretty MyApp.Funding

  ## Options

    * `--output` / `-o` — output file path (default: `api_manifest.json`)
    * `--pretty` — indent JSON for readability
    * `--app` — discover all modules in the given OTP app that export `__api__/0`

  ## Prerequisites

  This task requires `jason` for JSON encoding. Most Elixir projects already
  include it. If not, add `{:jason, "~> 1.4"}` to your deps.

  ## Module Resolution Order

    1. Module names passed as CLI arguments
    2. `--app` flag (discovers modules exporting `__api__/0`)
    3. `config :descripex, :manifest_modules` application env

  """

  use Mix.Task

  @default_output "api_manifest.json"

  @doc "Run the manifest export task."
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, module_args} =
      OptionParser.parse!(args,
        strict: [output: :string, pretty: :boolean, app: :string],
        aliases: [o: :output]
      )

    Mix.Task.run("compile", [])

    modules = resolve_modules(module_args, opts)
    manifest = Descripex.Manifest.build(modules)

    json =
      if opts[:pretty] do
        Jason.encode!(manifest, pretty: true)
      else
        Jason.encode!(manifest)
      end

    output_path = opts[:output] || @default_output
    File.write!(output_path, json)
    Mix.shell().info("Wrote manifest to #{output_path}")
  end

  # Resolves the module list from CLI args, --app flag, or config.
  defp resolve_modules(module_args, opts)

  defp resolve_modules([_ | _] = module_args, _opts) do
    Enum.map(module_args, fn name ->
      Module.concat([name])
    end)
  end

  defp resolve_modules([], opts) do
    cond do
      app = opts[:app] ->
        app_atom =
          try do
            String.to_existing_atom(app)
          rescue
            ArgumentError ->
              Mix.raise("Unknown application :#{app}")
          end

        discover_modules(app_atom)

      modules = Application.get_env(:descripex, :manifest_modules) ->
        modules

      true ->
        Mix.raise("""
        No modules specified. Use one of:

          mix descripex.manifest MyApp.Funding MyApp.Risk
          mix descripex.manifest --app my_app
          config :descripex, manifest_modules: [MyApp.Funding, MyApp.Risk]
        """)
    end
  end

  # Discovers all modules in the given OTP app that export __api__/0.
  defp discover_modules(app) do
    {:ok, modules} = :application.get_key(app, :modules)

    modules
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__api__, 0)
    end)
    |> case do
      [] ->
        Mix.raise("No Descripex-annotated modules found in application :#{app}")

      found ->
        found
    end
  end
end
