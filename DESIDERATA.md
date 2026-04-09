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

## Monitoring and invalidation

Persistent server mode should monitor the filesystem and invalidate or refresh cache state in near realtime.

The implementation should use a strong cross-platform file watching approach that relies on good native OS facilities where possible.

The watcher behavior should batch or debounce sensibly so that bursts of edits do not cause pathological reparsing.

CLI one-shot mode may still perform on-demand refresh without a long-running watcher.

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

### High-level query philosophy

Common repetitive code exploration tasks should not require the agent to write long, tedious Tree-sitter queries every time.

`ceretree` should therefore provide concise higher-level commands or presets for common exploration tasks such as:

- functions by name
- types by name
- calls by callee
- references by identifier-like name

But this must not replace the raw query path.

## Result sizing

Result limiting and paging are required.

Broad exploration RPCs should have:

- `limit`
- `offset`

The default limit should be `100`.

This matters both for performance and for keeping responses usable by AI agents.

## Context lookup for edits

The project must support a point-in-file context lookup operation.

Given a file path and coordinate, it should identify:

- the innermost relevant named node
- enclosing blocks
- enclosing symbols
- the start and end ranges of those scopes

This is important for agents because editing errors often come from not understanding exactly where a symbol or block starts and ends.

## Performance direction

The system should optimize for real codebase exploration, not toy examples.

Important performance directions include:

- persistent server reuse
- AST reuse
- incremental invalidation
- cached higher-level analysis results
- paging
- low-overhead multi-file search

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
