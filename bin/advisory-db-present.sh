#!/bin/sh
# Guard for `mix ci`: prove `mix deps.audit` had an advisory database to audit.
#
# `mix_audit` ships no advisories (its `priv/` is empty) — `MixAudit.Repo`
# git-clones the database at runtime and *discards* the clone's exit status. A
# failed clone leaves `Path.wildcard/1` matching zero advisory files, so
# `deps.audit` prints "No vulnerabilities found" and exits 0. This turns that
# silent no-op into a red step.
#
# Lives in a file rather than inline in the `ci` alias because Elixir 1.18's
# `mix cmd` joins its arguments into one string and re-parses them through the
# shell, dropping the quoting an inline `if …; then …; fi` needs (1.19+ instead
# passes argv straight to `System.cmd/3`). A script path survives both.
#
# The path is `MixAudit.Repo.repo_path/0` verbatim: `System.user_home()` +
# `.local/share/elixir-security-advisories-mirego` on every OS — mix_audit
# hardcodes it, it is not an XDG basedir lookup.
set -eu

db="${HOME}/.local/share/elixir-security-advisories-mirego/packages"

if [ -d "$db" ]; then
  exit 0
fi

echo "deps.audit ran against an empty advisory database - the result above is meaningless" >&2
echo "expected advisories at: $db" >&2
exit 1
