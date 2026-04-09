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
- Use `index.status` to inspect configured roots and recent cache metadata before issuing expensive searches.
- Use `symbols.overview` as the default high-level exploration command when you need a broad map of files, functions, methods, classes, interfaces, types, modules, or packages.
- Use `symbols.find` when you already know the symbol name or want a narrow lookup by kind.
- Use `calls.find` when you want callsites for a specific callee across many files.
- Use `query.common` for frequent agent-oriented searches that should stay shorter than raw Tree-sitter queries.
- Use `query` when you need a precise low-level Tree-sitter search pattern across many files.
- Use `limit` and `offset` early on large repositories so the agent can iterate instead of requesting huge result sets at once. If omitted, `limit` defaults to `100`.

## Recommended exploration flow

1. Call `system.describe`.
2. Call `roots.list` or `roots.add` as needed.
3. Call `index.status`.
4. Call `symbols.overview` on a narrow glob first.
5. Call `symbols.find` or `calls.find` when you already have a candidate name.
6. Call `query.common` for common cases that do not need raw query syntax.
7. Page broad result sets with `limit` and `offset`.
8. If the result is still too broad or you need a special structural pattern, fall back to `query`.

## Preferred persistent server lifecycle

- Choose a unique temporary Unix socket path yourself.
- Start the server once and give that process a long timeout so you can reuse it across many requests.
- Keep the server alive while doing other agent work between requests.
- Wait for readiness before the first request. Prefer curl retry flags instead of writing shell retry loops.
- Send simple HTTP `POST` requests to `/rpc`, carrying one JSON-RPC request body and expecting one JSON-RPC response body back.
- Use a curl-compatible client so the same flow works on Windows and Linux.
- Stop the server explicitly when finished and remove the socket path.
- Use `system.describe` to confirm readiness and inspect `process_id` if you need to verify that later requests are hitting the same server process.

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
