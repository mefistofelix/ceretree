# ceretree skill

Use `ceretree` as a fast code-exploration backend for source trees registered through JSON-RPC.

## Current state and transport direction

- Current builds support one-shot CLI JSON-RPC and persistent HTTP JSON-RPC server mode.
- Persistent server mode accepts `--server unix://path.sock` and `--server tcp://host:port`.
- Prefer Unix-socket HTTP for agent workflows because many agent runtimes can reissue independent HTTP requests easily, but cannot keep and reuse a subprocess stdio handle across separate tool calls.
- Keep JSON-RPC 2.0 as the message format for one-shot CLI and server mode so method names, responses and errors stay consistent.
- On Windows, if you use curl, call the real binary `curl.exe`, not the PowerShell alias `curl`.

## When to use which command

- Use `system.describe` first to discover supported methods, runtime mode, and compiled languages.
- Use `index.status` to inspect configured roots, recent cache metadata, and the reusable per-file analysis cache before issuing expensive searches.
- Use `symbols.overview` as the default high-level exploration command when you need a broad map of files, functions, methods, classes, interfaces, types, modules, or packages.
- Use `context.at` before edits when you need to know the exact enclosing function, type, or block at a coordinate.
- Use `symbols.find` when you already know the symbol name or want a narrow lookup by kind.
- Use `references.find` when you want fast syntactic identifier-style usages across many files.
- Use `calls.find` when you want callsites for a specific callee across many files.
- Use `query.common` for frequent agent-oriented searches that should stay shorter than raw Tree-sitter queries.
- Use `query` when you need a precise low-level Tree-sitter search pattern across many files.
- Use `limit` and `offset` early on large repositories so the agent can iterate instead of requesting huge result sets at once. If omitted, `limit` defaults to `100`.

## Recommended exploration flow

1. Call `system.describe`.
2. Call `roots.list` or `roots.add` as needed.
3. Call `index.status`.
4. Call `symbols.overview` on a narrow glob first.
5. Call `context.at` before editing a known location so you understand its containing symbol and scope.
6. Call `symbols.find`, `references.find`, or `calls.find` when you already have a candidate name.
7. Call `query.common` for common cases that do not need raw query syntax.
8. Page broad result sets with `limit` and `offset`.
9. If the result is still too broad or you need a special structural pattern, fall back to `query`.

## Cache-aware usage

- `symbols.overview`, `symbols.find`, `calls.find`, and `references.find` share the same reusable per-file analysis cache.
- The first broad exploration request on a file warms that cache; later symbol/call/reference requests on unchanged files should be cheaper.
- `query` stays uncached on purpose because its structure is arbitrary and low-level.
- If you want to confirm cache warmup on a large repository, call `index.status` after an exploration request and inspect `analysis_cache.files`.

## Preferred persistent server lifecycle

- Choose a unique temporary Unix socket path yourself.
- Start the server once and give that process a long timeout so you can reuse it across many requests.
- Keep the server alive while doing other agent work between requests.
- Wait for readiness before the first request. Prefer curl retry flags instead of writing shell retry loops.
- Send simple HTTP `POST` requests to `/rpc`, carrying one JSON-RPC request body and expecting one JSON-RPC response body back.
- Use a curl-compatible client so the same flow works on Windows and Linux.
- Stop the server explicitly when finished and remove the socket path.
- Use `system.describe` to confirm readiness and inspect `process_id` if you need to verify that later requests are hitting the same server process.

## How to use `context.at`

- Use `context.at` when you already have a file and an approximate coordinate and need to understand the real edit scope before reading or patching.
- `innermost` is the deepest named node at that coordinate. It tells you what syntactic element you are directly on.
- `blocks` is the enclosing block stack from outermost to innermost. Use it to understand control-flow and brace-delimited scope.
- `symbols` is the enclosing symbol stack from outermost to innermost. Use it to identify the containing package, type, function, method, class, struct, or similar declaration.
- Prefer `symbols` when deciding which definition you are inside.
- Prefer `blocks` when deciding how much local code to read around a conditional, loop, or nested statement region.
- Use the returned `start` and `end` points to decide which exact lines to inspect before editing.
- If `context.at` shows that the target point is inside a different symbol than expected, stop and re-anchor before editing.

## Edit-oriented workflow

1. Use `symbols.find` or `references.find` to identify candidate files and approximate positions.
2. Use `context.at` on the exact coordinate you plan to edit.
3. Read the enclosing symbol range returned by `context.at`.
4. Read any narrower inner block range if the change is local.
5. Only then prepare the edit.

## Preferred server commands

- Windows preferred:
  `ceretree.exe --server unix://C:/temp/ceretree.sock`
- Linux preferred:
  `./ceretree --server unix:///tmp/ceretree.sock`
- TCP fallback:
  `ceretree --server tcp://127.0.0.1:9000`

## Windows note

- In PowerShell, `curl` is often an alias and should not be assumed to support Unix sockets correctly.
- Prefer `curl.exe` on Windows when using Unix-socket HTTP.
- On Unix-like shells, prefer the normal `curl` binary.

## Curl examples

Windows Unix socket:

```text
curl.exe --retry 20 --retry-all-errors --retry-delay 0 --unix-socket C:/temp/ceretree.sock -H "content-type: application/json" -X POST --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"system.describe\"}" http://localhost/rpc
```

Linux Unix socket:

```text
curl --retry 20 --retry-all-errors --retry-delay 0 --unix-socket /tmp/ceretree.sock -H 'content-type: application/json' -X POST --data-binary '{"jsonrpc":"2.0","id":1,"method":"system.describe"}' http://localhost/rpc
```

TCP fallback:

```text
curl --retry 20 --retry-all-errors --retry-delay 0 -H "content-type: application/json" -X POST --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"index.status\"}" http://127.0.0.1:9000/rpc
```

## Why keep raw Tree-sitter queries available

High-level RPCs are faster to compose and easier to use repeatedly, but they intentionally cover only the most common exploration cases.

Raw `query` remains the escape hatch for:

- unusual syntactic patterns
- language-specific constructs
- custom capture sets
- investigations where a generic symbol overview is too lossy
- cases where `symbols.find`, `references.find`, `calls.find`, or `query.common` still do not express the exact structure you need

LLMs often do not remember Tree-sitter query syntax perfectly. Prefer `symbols.overview` first, then use `query` only when the task requires lower-level control.

`references.find` is syntactic, not semantic. Prefer it for fast codebase exploration, but do not treat it as a full cross-language definition/reference engine.

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
    "max_symbols":200,
    "limit":20,
    "offset":0
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
    "include":"**/*.go",
    "limit":20,
    "offset":0
  }
}
```

`context.at`

```json
{
  "jsonrpc":"2.0",
  "id":45,
  "method":"context.at",
  "params":{
    "language":"go",
    "path":"src/main.go",
    "roots":["C:/repo"],
    "row":286,
    "column":10
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
    "include":"**/*.go",
    "limit":20,
    "offset":0
  }
}
```

`references.find`

```json
{
  "jsonrpc":"2.0",
  "id":55,
  "method":"references.find",
  "params":{
    "language":"go",
    "name":"dispatch",
    "roots":["C:/repo"],
    "include":"**/*.go",
    "limit":20,
    "offset":0
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
    "include":"**/*.go",
    "limit":20,
    "offset":0
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
    "include":"**/*.go",
    "limit":20,
    "offset":0
  }
}
```
