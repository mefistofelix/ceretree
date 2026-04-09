# ceretree

`ceretree` must be rebooted around `JavaScript` running on `Bun`, while preserving the feature direction, agent workflows, and protocol ideas already validated in the previous implementation.

This file describes the desired end state, not the currently implemented state.

## Product goal

`ceretree` is a code exploration tool for AI coding agents.

It must let an agent inspect one or more source roots through a `JSON-RPC 2.0` protocol and support both:

- one-shot CLI usage
- persistent server usage

The tool is aimed at coding and code understanding scenarios such as:

- symbol discovery
- signature inspection
- finding callsites
- finding references
- understanding the parent block or symbol around a point before editing
- running low-level multi-file Tree-sitter queries when the higher-level RPCs are not enough

The raw multi-file Tree-sitter query capability must remain available as an escape hatch.

## Core architecture

The project should be reimplemented in `JavaScript` for `Bun`.

The high-level runtime should be Bun/JS because it gives us, in one stack:

- integrated `SQLite`
- integrated filesystem watching support
- integrated HTTP server support
- integrated Unix domain socket support
- a strong single-runtime story for Windows and Linux

Tree-sitter itself should not be consumed through a generic npm package abstraction if that would hide capabilities we need.

Instead, `ceretree` should use a native `N-API` binding compiled by us and shipped as part of the project build. That native layer should:

- be built with `zig cc`
- embed the Tree-sitter runtime
- embed all selected grammars
- expose the operations we need for parsing, querying, symbol extraction support, incremental reuse, and binary AST extraction or serialization support

The final released artifact should still feel self-contained from the `XProjectUser` perspective even if the internal implementation is now Bun/JS plus a native addon.

## Transport and protocol

The protocol should remain `JSON-RPC 2.0`.

The transport should be simple HTTP request/response.

One request must produce one response.

The canonical HTTP endpoint should be:

- `POST /rpc`

The HTTP body must contain exactly one JSON-RPC request object and the response body must contain exactly one JSON-RPC response object.

Batch JSON-RPC requests are not required.

The persistent server should support:

- `unix://absolute/path.sock`
- `tcp://host:port`

Both should be accepted through the CLI in the same style so the caller can choose the transport explicitly.

### Preferred transport

The preferred persistent transport is HTTP over Unix domain socket.

Rationale:

- many agent runtimes do not expose reusable persistent stdio process handles across separate tool calls
- an HTTP server on a caller-chosen Unix socket is easy to reattach to later from stateless commands
- the caller can choose a unique temporary socket path and manage cleanup
- it avoids TCP port namespace pollution when TCP is not needed

TCP should still be supported as a fallback where Unix sockets are inconvenient.

### Stdio

Persistent stdio server mode should not be the primary design target.

If present at all, it should be treated as secondary compatibility only, because it is less useful for many real agent runtimes than a reattachable HTTP transport.

## CLI modes

The CLI should support two primary modes:

- one-shot mode
- persistent server mode

### One-shot mode

One-shot mode should accept a raw JSON-RPC request either:

- as the first CLI argument
- or from stdin

This is useful for simple scripting, testing, and one-off inspection.

### Persistent server mode

Persistent server mode should be started with a single explicit flag, for example:

- `--server unix://...`
- `--server tcp://...`

The process should remain alive until terminated by the caller.

The server should expose enough runtime metadata through RPC to let the caller confirm that repeated requests are hitting the same live process.

## Agent workflow requirements

The tool must be strongly skill-friendly and agent-friendly.

The expected agent lifecycle must be explicitly supported and documented:

1. choose a temporary unique Unix socket path
2. start the server with a long timeout budget
3. wait for readiness
4. send many RPC requests over time
5. interleave those requests with other reasoning or tool calls
6. stop the server when done
7. delete the socket path

The system must be easy to drive with mainstream default tools already present on Windows and Linux.

The skill documentation must explain clearly that:

- on Windows, the real `curl.exe` should be preferred over PowerShell aliases
- the caller should use client retry capabilities for startup readiness rather than complex shell retry loops when possible
- the same persistent server can be reused across separate agent steps
- the caller may choose either `unix://...` or `tcp://...`

The skill documentation must also explain the lower-level raw query path so an agent can drop down from the high-level RPCs when needed.

## JSON-RPC contract

The protocol should stay small, stable, and explicit.

Every request must use `JSON-RPC 2.0`.

Example request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "system.describe",
  "params": {}
}
```

Example success response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {}
}
```

Example error response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "invalid params"
  }
}
```

The implementation should use normal JSON-RPC semantics for:

- parse errors
- invalid params
- method not found
- internal errors

### Common request parameters

Most exploration RPCs should converge on a common parameter vocabulary where it makes sense:

- `language`
- `roots`
- `include`
- `exclude`
- `limit`
- `offset`

Optional method-specific filters may include:

- `name`
- `kinds`
- `match_mode`
- `callee`
- `path`
- `row`
- `column`
- `preset`
- `query`
- `max_symbols`

`roots` should accept explicit root paths for the current call.

If omitted, the implementation may fall back to the registered roots.

### Common response shape

Exploration RPCs should prefer a response shape that is easy for agents to consume consistently.

The response should generally include:

- a `files` array
- a `summary` object

Where useful, each file entry should include:

- absolute `path`
- `root`
- root-relative path such as `relative`
- result arrays such as `symbols`, `calls`, `references`, or raw `captures`

The `summary` object should include enough metadata for paging and diagnostics, such as:

- `started_at`
- `duration_ms`
- `language`
- `limit`
- `offset`
- `files_scanned`
- `files_returned`
- result counters appropriate to the method

## Native binding requirements

The native Tree-sitter binding is a core product dependency, not an implementation detail to keep vague.

The native layer should expose a small explicit API that is sufficient for Bun/JS to implement the RPC surface cleanly.

It should support at least:

- listing embedded languages
- parsing text for a selected language
- executing Tree-sitter queries with captures
- extracting enough structured information to build symbol, call, and reference views
- point-based context lookup
- optional incremental update support
- binary AST export and import if that capability is technically viable in the chosen native design

The native layer should keep the Bun/JS surface simple rather than forcing complex Tree-sitter object choreography in JavaScript.

## Tree-sitter grammar strategy

Grammar handling should stay deterministic and fully owned by the project.

The build should:

- fetch grammar sources from upstream
- pin or resolve revisions explicitly
- generate grammar C sources during build
- compile the resulting code into the native binding

The project should continue to support both `tsx` and `typescript` as distinct grammar ids because they model different source syntaxes even when they share upstream repository structure.

## Roots and scope

The tool must query recursively across one or more configured roots.

It must support:

- adding roots
- removing roots
- listing roots

File selection must support:

- recursive walking by default
- relative include glob
- relative exclude glob
- `**` semantics

## Supported languages

The project should aim to support all official Tree-sitter languages that are practical to embed, with these as must-have languages:

- `bash`
- `batch`
- `c`
- `cpp`
- `go`
- `javascript`
- `lua`
- `php`
- `powershell`
- `python`
- `rust`
- `tsx`
- `typescript`

The grammar set should be bundled by us in the native binding build.

## Build system and native layer

The build should remain cold-bootstrappable and self-contained.

The build must:

- bootstrap Bun in portable form
- bootstrap Zig in portable form
- fetch the selected Tree-sitter grammar repositories or snapshots
- generate the grammar C sources during build
- compile the native binding and the embedded grammars with `zig cc`

We should continue to avoid depending on pre-generated grammar artifacts committed into the project.

The build should continue to prefer official upstream release binaries for tools when practical.

The build should still support cross-compilation and should continue to prefer producing both Windows x64 and Linux x64 release artifacts from Linux CI when practical.

## Cache and storage

The previous file-tree JSON cache layout should be considered replaceable.

For the Bun/JS reboot, the persistent cache should be designed around `SQLite`.

Rationale:

- it gives better structure than many loose files
- it is easier to reason about shared state
- it is easier to version and inspect
- it is a better base for future eviction, metadata, and query telemetry

The cache should live next to the executable in a `.ceretree-cache` folder as before.

The cache must support multiple simultaneously running `ceretree` server processes using the same cache directory.

The cache design should store enough metadata to validate entries safely across edits and across tool upgrades.

Where it is useful, `ceretree` should cache:

- roots and runtime state
- recent query metadata
- reusable analysis results
- binary AST data when the native binding exposes it safely

The design should treat binary AST reuse as an important capability because it can make generic raw queries much faster than reparsing every file on every request.

### Cache model

The cache should separate at least these logical layers:

- durable runtime state
- durable reusable analysis data
- durable AST-related data if technically viable
- in-memory hot process-local data for the active server

Durable runtime state should include things such as:

- registered roots
- last useful query metadata
- last useful overview metadata

Durable reusable analysis data should include things such as:

- symbol inventories
- call inventories
- syntactic reference inventories

The cache key model should be designed around the logical analyzed document, not just the filename string.

At minimum it should distinguish by:

- absolute path
- language id
- file modification metadata
- schema or cache version
- grammar or binary compatibility version where relevant

If binary AST storage is implemented, the format must be explicitly versioned so upgrades do not silently reuse incompatible data.

### Concurrency

Multiple `ceretree` server processes may share the same cache directory.

The chosen cache design must therefore avoid corruption and undefined behavior under concurrent readers and writers.

This is one reason `SQLite` is preferred for the durable shared cache.

## Monitoring and invalidation

Persistent server mode should monitor the filesystem and invalidate or refresh cache state in near realtime.

The implementation should use a strong cross-platform file watching approach that relies on good native OS facilities where possible.

The watcher behavior should batch or debounce sensibly so that bursts of edits do not cause pathological reparsing.

CLI one-shot mode may still perform on-demand refresh without a long-running watcher.

The monitoring layer should explicitly support these behaviors:

- coalescing bursts of edits
- invalidating stale cached entries
- reparsing only the affected files where possible
- keeping the server responsive while background invalidation happens

The monitoring design should prefer correctness first and should then optimize for lower-latency incremental refresh.

## RPC surface

The project should expose both low-level and high-level RPCs.

Low-level:

- raw Tree-sitter multi-file query

High-level:

- `system.describe`
- `index.status`
- `roots.list`
- `roots.add`
- `roots.remove`
- `symbols.overview`
- `symbols.find`
- `references.find`
- `calls.find`
- `context.at`
- `query.common`

Additional high-level RPCs may be added if they remove common Tree-sitter boilerplate and are clearly useful to coding agents.

### Required RPC contract

The following methods should be treated as first-class required methods for the reboot:

- `system.describe`
- `index.status`
- `roots.list`
- `roots.add`
- `roots.remove`
- `query`
- `query.common`
- `symbols.overview`
- `symbols.find`
- `references.find`
- `calls.find`
- `context.at`

### Method intent

`system.describe`

Should return process and capability metadata, including at least:

- tool name
- version
- supported methods
- supported languages
- active transport mode when in server mode
- process identifier
- cache location

`index.status`

Should return enough operational state to understand what the server currently knows, such as:

- registered roots
- cache status summary
- recent query summary
- recent overview summary
- analysis cache summary

`roots.list`

Should return the registered roots.

`roots.add`

Should add one or more roots to the registered root set.

`roots.remove`

Should remove one or more roots from the registered root set.

`query`

Should execute a raw multi-file Tree-sitter query across matching files and return captures, captured text, ranges, and summary metadata.

`query.common`

Should expose concise presets for common search tasks, while internally mapping those tasks to reusable higher-level logic or raw Tree-sitter query logic.

`symbols.overview`

Should return a broad symbol inventory for matching files and serve as the preferred first navigation step on unfamiliar code.

`symbols.find`

Should filter symbols by name and optional kinds with a stable `match_mode` contract.

`references.find`

Should return fast syntactic references rather than claiming full semantic reference resolution.

`calls.find`

Should find callsites by callee text or equivalent syntactic representation.

`context.at`

Should resolve the innermost node plus enclosing blocks and enclosing symbols around a file coordinate.

### High-level query philosophy

Common repetitive code exploration tasks should not require the agent to write long, tedious Tree-sitter queries every time.

`ceretree` should therefore provide concise higher-level commands or presets for common exploration tasks such as:

- functions by name
- types by name
- calls by callee
- references by identifier-like name

But this must not replace the raw query path.

### Preset direction

At minimum, `query.common` should cover these preset categories:

- `functions.by_name`
- `types.by_name`
- `references.by_name`
- `calls.by_name`

Additional presets may be added if they are common and materially reduce repetitive raw query authoring for agents.

## Result sizing

Result limiting and paging are required.

Broad exploration RPCs should have:

- `limit`
- `offset`

The default limit should be `100`.

This matters both for performance and for keeping responses usable by AI agents.

Large responses should prefer predictable truncation and explicit summary metadata over returning arbitrarily huge payloads.

## Context lookup for edits

The project must support a point-in-file context lookup operation.

Given a file path and coordinate, it should identify:

- the innermost relevant named node
- enclosing blocks
- enclosing symbols
- the start and end ranges of those scopes

This is important for agents because editing errors often come from not understanding exactly where a symbol or block starts and ends.

The response should make the nesting obvious enough that an agent can decide what exact source range should be read or edited next.

## Performance direction

The system should optimize for real codebase exploration, not toy examples.

Important performance directions include:

- persistent server reuse
- AST reuse
- incremental invalidation
- cached higher-level analysis results
- paging
- low-overhead multi-file search

The system should prefer a persistent server plus hot cache path for repeated exploration work on the same codebase.

## Testing direction

The test suite must be black-box and CLI/server oriented.

It should cover both:

- one-shot usage
- persistent server usage

It should include realistic exploration scenarios such as:

- finding all calls to a function
- finding functions with a given signature pattern
- finding references to an identifier
- finding the containing block or symbol around a point
- running a raw multi-file query

We should also run practical tests on real public codebases, including examples such as:

- `redis`
- `wordpress`

The purpose is to validate both correctness and response sizing behavior on real repositories.

The test plan should also include persistent server behavior such as:

- readiness retry from the client side
- repeated requests to the same live process
- interleaved requests over time
- concurrent requests where practical
- cache reuse across multiple requests
- invalidation after file changes once monitoring exists

## Skill and MCP friendliness

The project must remain friendly to AI agent skills and should remain easy to adapt into `MCP` if useful later.

The skill documentation must be treated as a first-class deliverable.

It must explain clearly:

- what the server does
- which transport to prefer and why
- how to start it
- how to wait for readiness
- how to send requests correctly on Windows and Linux
- how to use the high-level RPCs first
- when to fall back to the raw query RPC
- how paging works
- how to use persistent reuse correctly

The skill should help an agent avoid common mistakes rather than merely listing commands.

## Spec-driven restart intent

This document should be detailed enough that the project can be restarted from zero implementation while preserving:

- the validated transport choices
- the validated agent workflow
- the validated RPC surface
- the validated paging behavior
- the validated context lookup behavior
- the validated distinction between high-level RPCs and raw query escape hatch
- the storage and monitoring direction chosen for the reboot

The implementation may change completely, but these product-level and protocol-level decisions should remain stable unless intentionally revised.
