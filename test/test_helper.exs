# Enable docs so fixture modules compiled in tests have @doc/@moduledoc metadata
# accessible via Code.fetch_docs/1 (ExUnit defaults to docs: false)
Code.compiler_options(docs: true)

ExUnit.start()
