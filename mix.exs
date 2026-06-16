defmodule Descripex.MixProject do
  use Mix.Project

  @version "0.11.0"
  @source_url "https://github.com/ZenHive/descripex"

  def project do
    [
      app: :descripex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [docs: true],
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :jason]],
      aliases: aliases(),
      docs: docs(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Dev/test tooling
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:earmark_parser, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},

      # Code analysis tools
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},

      # Tidewave for Claude Code MCP integration (non-Phoenix needs bandit)
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.11", only: :dev},

      # JSON encoding (for mix descripex.manifest task)
      {:jason, "~> 1.4", only: [:dev, :test], runtime: false},

      # JSON Schema from Elixir type syntax (compile-time only)
      {:json_spec, "~> 1.1"}
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4020) end)'"
      ]
    ]
  end

  defp docs do
    [
      main: "Descripex",
      extras: ["README.md", "CONSUMING.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      description:
        "Self-describing API declarations for Elixir — generates docs, machine-readable hints, and runtime introspection from a single macro call.",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CONSUMING.md LICENSE)
    ]
  end
end
