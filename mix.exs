defmodule Descripex.MixProject do
  use Mix.Project

  @version "0.12.0"
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
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Code analysis tools
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},

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
      ],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and the coverage
      # pass so it stays quick on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "ex_dna --max-clones 0",
        # `preferred_envs` (cli/0) is ignored for alias steps — set MIX_ENV via
        # `env` (Elixir 1.20's `mix cmd` no longer parses a leading VAR=val prefix).
        "cmd env MIX_ENV=test mix test.json --exclude integration"
      ],
      # Portable gate — every step here runs on a bare clone with nothing but the
      # repo and a BEAM: CI, a fork, a contributor's laptop. This is what
      # .github/workflows/harness.yml invokes. Coverage floor 70 matches the
      # family convention (measured baseline: 93.13%).
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        # `--exit` is what makes sobelow gate: without it a finding is printed and
        # the task still returns 0, so the step can never fail. `low` is sobelow's
        # own default for a bare `--exit`, spelled out here to keep it visible.
        "sobelow --skip --exit low",
        # `mix_audit` ships no advisories (its `priv/` is empty) — `MixAudit.Repo`
        # git-clones the database at runtime and *discards* the clone's exit
        # status. A failed clone therefore leaves `Path.wildcard/1` matching zero
        # advisory files, and `deps.audit` prints "No vulnerabilities found" and
        # exits 0. The guard below turns that silent no-op into a red step. On a
        # runner the clone is fresh every time (nothing caches ~/.local/share), so
        # this is the only thing standing between us and a meaningless green.
        "deps.audit",
        "cmd sh -c 'if test -d $HOME/.local/share/elixir-security-advisories-mirego/packages; then exit 0; else echo deps.audit ran against an empty advisory database - the result above is meaningless; exit 1; fi'",
        "cmd env MIX_ENV=test mix test.json --cover --cover-threshold 70 --summary-only --exclude integration",
        "dialyzer"
      ],
      # Operator/reviewer gate — `ci` plus the two checks that read this
      # workstation's layout and therefore cannot run on a runner. Both are
      # host-local by nature, not by accident, so vendoring the scripts into the
      # repo would not make them portable:
      #   * advisory.fresh proves the *long-lived* local advisory mirror is at
      #     upstream tip. Only a machine that keeps the clone between runs can
      #     drift; a runner re-clones from scratch every time, so the currency
      #     question there reduces to "did the clone succeed", which the guard
      #     inside `ci` answers.
      #   * agents.check re-renders AGENTS.md from CLAUDE.md, which inlines
      #     `@~/.claude/includes/*.md` — paths that exist only in the operator's
      #     home directory.
      "precommit.full": ["advisory.fresh", "ci", "agents.check"],
      # mix_audit discards its sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports green. Prove freshness before auditing.
      # This repo's `deps.audit` reports clean — no ignore file needed.
      "advisory.fresh": [
        "cmd ~/_DATA/code/onchain-stack/bin/advisory-freshness.sh"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered
      # output, not mtimes, so drift in a transitive @-import is caught too.
      # AGENTS.md is what the cross-family (codex/cursor/grok) reviewers read;
      # a stale render makes them gate against rules that already changed.
      "agents.check": [
        "cmd ~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check"
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
