# ceretree

`ceretree` is a JSON-RPC CLI for recursive source-tree inspection built in Go on top of `github.com/tree-sitter/go-tree-sitter`.

## Current slice

The current implementation provides:

- one-shot CLI execution through a raw JSON-RPC request passed as the first argument or through stdin
- HTTP JSON-RPC server mode through `--server unix://path.sock` or `--server tcp://host:port`
- one HTTP `POST` request produces one JSON-RPC response on `/rpc`
- Unix domain socket is the preferred persistent transport for agent workflows, with TCP as a fallback
- UTF-8 BOM on stdin is tolerated in one-shot CLI mode for better Windows PowerShell interoperability
- persistent root registration in `bin/.ceretree-cache/state.json`
- recursive file discovery with relative include and exclude globs supporting `**`
- Tree-sitter query execution against grammars statically linked into the final binary
- symbol overview extraction for common agent navigation workflows
- symbol filtering by name and kind for fast codebase lookup
- point-in-file context lookup for block and parent symbol discovery before edits
- syntactic reference search for identifier and selector-style usages across many files
- callsite discovery for common function and method usage exploration
- common high-level query presets for agent-friendly workflows
- result paging through `limit` and `offset` on exploration RPCs, with `limit` defaulting to `100`
- index status inspection for cached roots and recent query metadata
- persistent per-file analysis cache for `symbols.overview`, `symbols.find`, `calls.find`, and `references.find`
- incremental grammar regeneration through `tree-sitter-cli` only when the cached grammar inputs change
- portable bootstrap under `build_cache/` for Go, Zig, Bun, and the official `tree-sitter-cli` release binaries fetched directly from upstream release URLs

Current supported grammars:

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

Current scope limits:

- filesystem watch and realtime reload are not implemented yet
- cache stores runtime state, recent query metadata, and reusable per-file analysis snapshots for symbol/call/reference exploration

## Build architecture

The build is intentionally self-bootstrapping and incrementally reuses grammar work from `build_cache/` when the requested grammar revision and toolchain inputs have not changed.

The pipeline is:

1. bootstrap portable toolchains into `build_cache/`
2. resolve each grammar ref from `src/GRAMMARS.txt` to a concrete commit with `git ls-remote` and download a source snapshot archive from GitHub codeload
3. install grammar-repo and grammar-local JS dependencies with Bun when required
   using `bun install --ignore-scripts` because grammar generation only needs package resolution, not native Node addon build hooks
4. run `tree-sitter generate` only when the cached grammar generation sentinel is stale
5. compile generated `parser.c` plus optional `scanner.c` or `scanner.cc` with Zig
6. build a local static grammar registry archive
7. compile the final Go binary with `cgo` against that local archive

This keeps the release binary self-contained while avoiding pre-generated grammar artifacts checked into the project.

Grammar cache invalidation is driven by simple per-grammar sentinels under `build_cache/grammar_state/`:

- source snapshot download is skipped when the resolved commit sentinel already matches
- `bun install --ignore-scripts` is skipped when the Bun sentinel already matches the current grammar input key
- `tree-sitter generate` is skipped when the generated C sentinel already matches and `src/parser.c` is present

## Tool bootstrap

`build.bat` currently bootstraps:

- Go `1.26.2`
- Zig `0.15.2`
- Bun `1.3.11`
- `tree-sitter-cli` `v0.26.8` from the official Windows x64 release asset

On Windows, a single `build.bat` run now produces both:

- `bin/ceretree.exe` for Windows x64
- `bin/ceretree` as a static ELF for Linux x64 via cross-compilation

`build.sh` bootstraps the same toolchain set for Linux using the official Linux x64 release asset.

Portable tool state is stored under:

- `build_cache/toolchains/`
- `build_cache/tools/`
- `build_cache/grammars/`
- `build_cache/generated/`

## Grammar manifest

Grammar repository selections live in [`src/GRAMMARS.txt`](C:/Users/Michele/Desktop/ceretree/src/GRAMMARS.txt).

Each line is:

```text
language|repo_url|revision|subdirectory|needs_bun
```

Meaning:

- `language`: RPC language id and generated registry key
- `repo_url`: grammar repository
- `revision`: git ref resolved during build to a concrete commit, typically `HEAD` in the current floating setup
- `subdirectory`: grammar root inside the repository, `.` when the repo root is the grammar root
- `needs_bun`: `1` when the grammar repo needs JS package installation before `tree-sitter generate`

The current manifest intentionally uses floating `HEAD` revisions. Each build resolves those refs to concrete commits, reuses the cached snapshot when the resolved commit is unchanged, and refreshes automatically when upstream moves.

## Build

Windows default native build:

```bat
build.bat
```

Windows optional targets:

```bat
build.bat windows
build.bat linux
build.bat all
```

Default output:

- `bin\ceretree.exe`

Optional outputs:

- `bin\ceretree` as a static Linux x64 ELF

Linux default native build:

```sh
./build.sh
```

Linux optional targets:

```sh
./build.sh linux
./build.sh windows
./build.sh all
```

CI uploads build artifacts only for an explicit Git tag release. A workflow run triggered by a pushed tag, or a manual run with a tag input, uploads:

- `ceretree-windows-x64.exe`
- `ceretree-linux-x64`

## Tests

Windows:

```bat
test.bat
```

Linux:

```sh
./test.sh
```

The test entrypoints do not bootstrap the build. Run the appropriate build first, then run the platform test script against the existing binary.

The black-box tests exercise:

- `system.describe`
- `index.status`
- `roots.add`
- `query` on `src/main.go`
- `symbols.overview` on `src/main.go`
- `symbols.find` on `src/main.go`
- `context.at` on `src/main.go`
- `references.find` on `src/main.go`
- `calls.find` on `src/main.go`
- `query.common` on `src/main.go`
- one-shot stdin with UTF-8 BOM
- persistent HTTP server mode over Unix socket
- persistent HTTP server mode over TCP

The build no longer compiles `tree-sitter-cli` locally. It downloads the official upstream release binary for the current platform and uses Bun as the JavaScript runtime for `tree-sitter generate`.

For grammars that depend on JavaScript packages, the build runs `bun install --ignore-scripts` in the grammar repository root and, when present, again in the grammar subdirectory. This matters for repositories such as `tree-sitter-typescript`, where both `tsx/grammar.js` and `typescript/grammar.js` resolve dependencies from the repository root.

## JSON-RPC methods

Server transport:

- start with `ceretree --server unix://path.sock`
- or start with `ceretree --server tcp://127.0.0.1:9000`
- send HTTP `POST` requests to `/rpc`
- request and response bodies stay JSON-RPC `2.0`
- use curl retry flags to wait for readiness instead of shell retry loops when possible

Unix-socket example on Windows with `curl.exe`:

```bat
ceretree --server unix://C:/temp/ceretree.sock
curl.exe --retry 20 --retry-all-errors --retry-delay 0 --unix-socket C:/temp/ceretree.sock -H "content-type: application/json" -X POST --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"system.describe\"}" http://localhost/rpc
```

Unix-socket example on Linux:

```sh
./ceretree --server unix:///tmp/ceretree.sock
curl --retry 20 --retry-all-errors --retry-delay 0 --unix-socket /tmp/ceretree.sock -H 'content-type: application/json' -X POST --data-binary '{"jsonrpc":"2.0","id":1,"method":"system.describe"}' http://localhost/rpc
```

TCP example:

```text
ceretree --server tcp://127.0.0.1:9000
curl --retry 20 --retry-all-errors --retry-delay 0 -H "content-type: application/json" -X POST --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"system.describe\"}" http://127.0.0.1:9000/rpc
```

`system.describe`

Returns executable metadata, cache location, supported languages, and currently implemented methods.
The response also includes `process_id` and the active server target when the binary is running in server mode.

`index.status`

Returns the configured roots plus cache metadata such as the last query, the last symbol overview summary, and the current per-file analysis cache inventory when present.

`roots.add`

```json
{"jsonrpc":"2.0","id":1,"method":"roots.add","params":{"paths":["."]}}
```

`roots.list`

Returns the registered roots.

`roots.remove`

Removes one or more registered roots.

`query`

```json
{
  "jsonrpc":"2.0",
  "id":1,
  "method":"query",
  "params":{
    "language":"go",
    "query":"(package_identifier) @name",
    "roots":["C:/repo"],
    "include":"**/*.go",
    "exclude":"**/vendor/**",
    "limit":50,
    "offset":0
  }
}
```

The `query` method parses every matching file under the selected roots and returns the captured nodes with byte offsets, points, kinds, and captured text. `limit` and `offset` page the returned file list, and `limit` defaults to `100`.

`query.common`

```json
{
  "jsonrpc":"2.0",
  "id":1,
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

Provides higher-level preset searches for common agent workflows. Current presets are:

- `functions.by_name`
- `types.by_name`
- `references.by_name`
- `calls.by_name`

`symbols.overview`

```json
{
  "jsonrpc":"2.0",
  "id":1,
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

Returns a high-level symbol inventory for matching files, including symbol kind, name, container, signature preview, and byte/point ranges. This is intended as the fast, agent-friendly entry point before falling back to raw Tree-sitter queries.

`symbols.find`

```json
{
  "jsonrpc":"2.0",
  "id":1,
  "method":"symbols.find",
  "params":{
    "language":"go",
    "name":"handle_query",
    "kinds":["function"],
    "roots":["C:/repo"],
    "include":"**/*.go",
    "match_mode":"exact",
    "limit":20,
    "offset":0
  }
}
```

Filters the symbol inventory by name and optional kinds. `match_mode` currently supports `exact`, `contains`, `prefix`, `suffix`, and `regex`. `limit` and `offset` page the returned file list, and `limit` defaults to `100`.

`context.at`

```json
{
  "jsonrpc":"2.0",
  "id":1,
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

Returns the innermost named node at a file coordinate plus enclosing blocks and parent symbols. This is useful before edits when an agent needs to understand which function, method, class, struct, or scope actually contains the target position.

`calls.find`

```json
{
  "jsonrpc":"2.0",
  "id":1,
  "method":"calls.find",
  "params":{
    "language":"go",
    "callee":"invalid_params",
    "roots":["C:/repo"],
    "include":"**/*.go",
    "match_mode":"exact",
    "limit":20,
    "offset":0
  }
}
```

Finds call expressions by callee text across matching files and returns the matched expression plus byte and point ranges. `limit` and `offset` page the returned file list, and `limit` defaults to `100`.

`references.find`

```json
{
  "jsonrpc":"2.0",
  "id":1,
  "method":"references.find",
  "params":{
    "language":"go",
    "name":"dispatch",
    "roots":["C:/repo"],
    "include":"**/*.go",
    "match_mode":"exact",
    "limit":20,
    "offset":0
  }
}
```

Finds syntactic references by identifier-like node text across matching files and returns the matched expression plus byte and point ranges. This is intentionally a fast Tree-sitter-based search, not a semantic LSP reference engine. `limit` and `offset` page the returned file list, and `limit` defaults to `100`.

## Agent skill

[`src/SKILL.md`](C:/Users/Michele/Desktop/ceretree/src/SKILL.md) documents how an AI agent can use `ceretree` efficiently.

Recommended flow:

- start with `system.describe`
- inspect `index.status`
- use `symbols.overview` for broad navigation
- use `context.at` before edits when exact block ownership matters
- use `symbols.find` for named symbol lookup
- use `references.find`, `calls.find`, or `query.common` for common usage patterns
- use `limit` and `offset` on large codebases to page through broad results instead of pulling everything at once
- use `query` for low-level or unusual cases where the high-level RPCs are not enough
- for persistent workflows, prefer `--server unix://...` plus `curl` or `curl.exe`
