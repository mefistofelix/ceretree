# ceretree skill

Use `ceretree` as a fast code-exploration backend for source trees registered through JSON-RPC.

## When to use which command

- Use `system.describe` first to discover supported methods, runtime mode, and compiled languages.
- Use `index.status` to inspect configured roots and recent cache metadata before issuing expensive searches.
- Use `symbols.overview` as the default high-level exploration command when you need a broad map of files, functions, methods, classes, interfaces, types, modules, or packages.
- Use `symbols.find` when you already know the symbol name or want a narrow lookup by kind.
- Use `calls.find` when you want callsites for a specific callee across many files.
- Use `query.common` for frequent agent-oriented searches that should stay shorter than raw Tree-sitter queries.
- Use `query` when you need a precise low-level Tree-sitter search pattern across many files.

## Recommended exploration flow

1. Call `system.describe`.
2. Call `roots.list` or `roots.add` as needed.
3. Call `index.status`.
4. Call `symbols.overview` on a narrow glob first.
5. Call `symbols.find` or `calls.find` when you already have a candidate name.
6. Call `query.common` for common cases that do not need raw query syntax.
7. If the result is still too broad or you need a special structural pattern, fall back to `query`.

## Why keep raw Tree-sitter queries available

High-level RPCs are faster to compose and easier to use repeatedly, but they intentionally cover only the most common exploration cases.

Raw `query` remains the escape hatch for:

- unusual syntactic patterns
- language-specific constructs
- custom capture sets
- investigations where a generic symbol overview is too lossy
- cases where `symbols.find`, `calls.find`, or `query.common` still do not express the exact structure you need

LLMs often do not remember Tree-sitter query syntax perfectly. Prefer `symbols.overview` first, then use `query` only when the task requires lower-level control.

## Example requests

`system.describe`

```json
{"jsonrpc":"2.0","id":1,"method":"system.describe"}
```

`index.status`

```json
{"jsonrpc":"2.0","id":2,"method":"index.status"}
```

`symbols.overview`

```json
{
  "jsonrpc":"2.0",
  "id":3,
  "method":"symbols.overview",
  "params":{
    "language":"go",
    "roots":["C:/repo"],
    "include":"**/*.go",
    "exclude":"**/vendor/**",
    "max_symbols":200
  }
}
```

`symbols.find`

```json
{
  "jsonrpc":"2.0",
  "id":4,
  "method":"symbols.find",
  "params":{
    "language":"go",
    "name":"handle_query",
    "kinds":["function"],
    "roots":["C:/repo"],
    "include":"**/*.go"
  }
}
```

`calls.find`

```json
{
  "jsonrpc":"2.0",
  "id":5,
  "method":"calls.find",
  "params":{
    "language":"go",
    "callee":"invalid_params",
    "roots":["C:/repo"],
    "include":"**/*.go"
  }
}
```

`query.common`

```json
{
  "jsonrpc":"2.0",
  "id":6,
  "method":"query.common",
  "params":{
    "language":"go",
    "preset":"functions.by_name",
    "name":"handle_query",
    "roots":["C:/repo"],
    "include":"**/*.go"
  }
}
```

`query`

```json
{
  "jsonrpc":"2.0",
  "id":7,
  "method":"query",
  "params":{
    "language":"go",
    "query":"(call_expression function: (identifier) @callee (#eq? @callee \"Open\"))",
    "roots":["C:/repo"],
    "include":"**/*.go"
  }
}
```
