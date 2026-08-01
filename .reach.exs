# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# Flat single-namespace library (`Descripex.*`): the `api` macro (descripex.ex),
# progressive-disclosure helpers (describe.ex, discoverable.ex), and manifest/MCP
# introspection (manifest.ex, mcp.ex) are co-equal, mutually-consulted runtime
# modules with no facade/internal or generator/output split. The one Mix task
# (lib/mix/tasks/descripex.manifest.ex) depends on the runtime lib one-way, as
# any packaging task does — not a boundary worth enforcing. No `layers`/`deps`.
[
  smells: [strict: true]
]
