# AGENTS.md

This file provides coding conventions and rules for AI agents working on this repository.
The project-specific context (architecture, commands, module structure) is in CLAUDE.md.

---

## CRITICAL: ALWAYS WRITE TESTS

**Every feature MUST have tests, even if the specs don't explicitly mention them.**

- Write unit tests for pure functions
- Write tests for validations and error cases
- Write tests for edge cases (nil values, empty strings, boundary conditions)
- NEVER skip tests because "the spec doesn't mention them"
- NEVER consider a task complete without tests

**Testing is not optional.** If you implement a feature without tests, you have not completed the task.

## CRITICAL: NEVER HIDE TEST FAILURES

**TESTS THAT HIDE ERRORS ARE WORSE THAN NO TESTS AT ALL**

```elixir
# FORBIDDEN - NEVER WRITE THESE:
case result do
  {:ok, _} -> assert true
  {:error, _} -> assert true  # Makes ALL failures pass silently!
end

# CORRECT PATTERNS:
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :specific_expected_error} -> :ok
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

## CRITICAL: MINIMALIST APPROACH

**DO EXACTLY WHAT IS ASKED - NOTHING MORE, NOTHING LESS**

- NO proactive features or improvements unless explicitly requested
- NO additional error handling beyond what's needed
- NO refactoring unless specifically requested
- ONLY implement the exact feature/fix requested

## Code Style Guidelines

- **Elixir**: Follow standard Elixir conventions
  - Use `mix format` before committing
  - Add `@moduledoc` for all modules
  - Use typespecs for public functions
  - Pattern match in function heads when possible
  - Prefer pipe operator for data transformations

- **Error Handling**: Use `{:ok, result}` / `{:error, reason}` tuples

- **Testing**: Write comprehensive tests
  - Unit tests for pure functions
  - Test error scenarios
  - Use descriptive test names
  - Group related tests with `describe` blocks

- **TypeSpec Requirements**
  - Define specs for all public functions
  - Dialyzer checks must pass with 0 warnings

## Private Function Documentation

Private functions (`defp`) should have `@doc false` and a comment explaining their purpose:

```elixir
# Correct: @doc false + explanatory comment
@doc false
# Normalizes the input map by converting string keys to atoms
defp normalize_input(map) do
  Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
end

# Correct: trivial one-liners can skip the comment
@doc false
defp add(a, b), do: a + b
```

## Development Philosophy

- **Simplicity First**: Minimal complexity for required functionality
- **Explicit over implicit**: Clear function calls and data flow
- **Simple over clever**: Avoid premature optimization, prefer readable code
- **Composable**: Small, verifiable functions that build complex operations

### TODO Comment Requirements

All temporary implementations MUST be marked with TODO:
- Instead of: "For now, we use..."
- Write: "TODO: For now, we use..."

### No Magic Numbers

All numeric literals must be named constants or have explanatory comments.

## Elixir Runtime Patterns

- **List access:** Use `Enum.at(list, i)` not `list[i]` (ArgumentError)
- **Empty checks:** Use `Enum.empty?(list)` not `length(list) == 0` (`length/1` is O(n))
- **No `else if`:** Use `cond do` for multiple conditions
- **Atoms from user input:** NEVER `String.to_atom(user_input)` (memory leak)

## Library Design

- Libraries are NOT applications
- NEVER use `Application.get_env/2` or `System.get_env/1` in library code
- Always pass configuration explicitly via function arguments

## Git Commit Configuration

**Format**: conventional-commits

```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore

## Shell Safety

- Never use `rm` (including `rm -rf`)
- Never run `mix deps.clean`, `mix deps.clean --all`, `mix deps.unlock --all`, or `mix clean`

## Build, Test, and Development Commands

```bash
mix deps.get                      # Fetch dependencies
mix compile                       # Compile library code
mix test                          # Run tests
mix format                        # Format code (Styler plugin)
mix format --check-formatted      # CI-style formatting check
mix credo                         # Static analysis
mix dialyzer                      # Type analysis
mix docs                          # Generate HexDocs locally
```
