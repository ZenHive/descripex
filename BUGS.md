# Known Bugs

Running log of confirmed defects. Newest first. Promote to `rmap new` tasks when fixing.

---

## 1. ✅ FIXED in 0.13.0 — Spec-derived param schemas ship silently typeless for `nonempty_list(...)` and union element types — MCP clients then stringify the argument

> **Resolved 2026-08-22 (Task 33).** `safe_convert/1` now runs a two-stage
> conversion: an AST pre-pass folds `nonempty_list(T)` / `[T, ...]` → `[T]` and
> rewrites `module()`/`node()` → `atom()`, and the converter tries json_spec on the
> whole type before decomposing a rejected union (shared schema when the members
> agree, `anyOf` when they differ). `Descripex.typeless_params/1` makes whatever
> still goes untyped queryable. The record below is kept as the discovery
> narrative and the pre-fix probe table.


- **Severity:** moderate (an `api()`-exposed function with such a param is advertised over MCP but is provably uncallable with the documented argument — the client sends a JSON array, the callee receives its string form. Reproducible, 100%. Two failure surfaces stack: an upstream mapping gap and this library swallowing it.)
- **Surface:** `Descripex.safe_convert/1` (`lib/descripex.ex:625`) → `JSONSpec.convert/1` (`json_spec ~> 1.1`), consumed via `fill_param_schemas_from_spec/2`.
- **Discovered:** 2026-08-20, registering a project through harness's `dispatch-register_project` MCP tool. Origin: zen_websocket → harness → here.
- **Tracked as:** Task 33 (`rmap show 33`) — filed 2026-08-22, verified against `json_spec ~> 1.1` in this checkout.

### Repro

Probed directly against `JSONSpec.convert/1` in this checkout (ASTs pre-normalized through `normalize_remote_aliases/1`):

```
# converts today
[String.t()]                       -> %{"items" => %{"type" => "string"}, "type" => "array"}
list(String.t())                   -> %{"items" => %{"type" => "string"}, "type" => "array"}
:buy | :sell                       -> %{"enum" => ["buy", "sell"], "type" => "string"}
String.t() | nil                   -> %{"type" => "string"}

# raises ArgumentError
nonempty_list(String.t())          -> ** unsupported type expression
nonempty_list(atom())              -> ** unsupported type expression
nonempty_list(atom() | String.t()) -> ** unsupported type expression
[String.t(), ...]                  -> ** unsupported type expression
atom() | String.t()                -> ** unsupported union type
integer() | String.t()             -> ** unsupported union type
[atom() | String.t()]              -> ** unsupported union type
```

The two converting union forms matter for the fix: their *members* raise
standalone (`:buy` and `nil` are not convertible types), so any per-member
union fold must run only after a whole-union attempt, never instead of one.

Live consequence, `Harness.Dispatch.register_project/8` — one `@spec`, two list params, only one typed:

| Param | `@spec` type | Emitted JSON Schema |
|---|---|---|
| `warm_paths` | `[String.t()]` | `{"type": "array", "items": {"type": "string"}}` |
| `languages` | `nonempty_list(atom() \| String.t())` | `{"description": "..."}` — no `type` |

Calling the tool with `languages: ["elixir"]` delivered the literal string `["elixir"]` to the callee, which rejected it. Registration only succeeded via a hand-rolled JSON-RPC `tools/call` carrying a real array.

### Two layers

1. **`json_spec` (dannote, upstream)** supports only the `[T]` and `list(T)` list forms — `nonempty_list(T)` fails for *every* `T`, and so does the `[T, ...]` literal. On unions it supports exactly two shapes, all-atom (`:buy | :sell` → enum) and nullable (`T | nil`); **every other union raises, anywhere it appears** — as a list element (`[atom() | String.t()]`) *and* as a bare top-level param type (`atom() | String.t()`). This is the broader miss: it is not list-specific.
2. **descripex** — `safe_convert/1` rescues `ArgumentError` and returns `:skip`, so the param ships **silently typeless**. `:skip` is the right call for genuinely inexpressible types (tuples, structs, bitstrings — the cases its rescue comment enumerates); here it hides a type that *is* expressible. There is no warning and no manifest-level "N params went typeless" signal, so nothing surfaces until an MCP client stringifies the argument at runtime.

### Direction

**Task 33's body is authoritative on the fix.** In outline, and local to this
repo — independent of dannote's release cycle (a PR to `dannote/json_spec` for
the underlying forms is the clean complement, not the prerequisite):

- **AST pre-pass** (`normalize_remote_aliases/1` and friends — `Macro.prewalk`,
  AST in / AST out): fold `nonempty_list(T)` and `[T, ...]` down to `[T]`.
  Unions cannot be handled here; deciding one requires comparing *converted*
  schemas, and `anyOf` has no type-AST spelling.
- **Converter step** (`safe_convert/1`): try the whole union first, so the enum
  and nullable forms keep working; only on `ArgumentError` drop `nil` members,
  convert the rest, and emit the shared schema if they agree or `anyOf` if they
  differ. Do **not** "reduce to the widest expressible member" — that is lossy
  and meaningless for `integer() | String.t()`. Folding `atom() | String.t()`
  is sound because both members convert to `%{"type" => "string"}`, i.e. because
  they *agree*, not because one is wider.

Independently — and this is the part that let the gap ship unnoticed — distinguish "inexpressible, correctly skipped" from "expressible but the converter choked". The second deserves a compile-time warning or a queryable count, so a typeless param on an `api()` surface is visible before an MCP client trips over it.
