# ceretree

`ceretree` is a JSON-RPC CLI for recursive source-tree inspection built in Go on top of `github.com/tree-sitter/go-tree-sitter`.

## Current slice

The current implementation provides:

- one-shot CLI execution through a raw JSON-RPC request passed as the first argument or through stdin
- persistent root registration in `bin/.ceretree-cache/state.json`
- recursive file discovery with relative include and exclude globs supporting `**`
- Tree-sitter query execution against grammars statically linked into the final binary
- build-time grammar regeneration on every build through `tree-sitter-cli`
- portable bootstrap under `build_cache/` for Go, Zig, rustup/cargo, Bun, and `tree-sitter-cli`

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

- server mode is not implemented yet
- filesystem watch and realtime reload are not implemented yet
- cache currently stores runtime state and query metadata, not reusable serialized syntax trees
- release packaging and GitHub release automation are not implemented yet

## Build architecture

The build is intentionally self-bootstrapping and always regenerates grammar C sources before compiling the Go binary.

The pipeline is:

1. bootstrap portable toolchains into `build_cache/`
2. fetch grammar repositories from `GRAMMARS.txt`
3. install grammar-local JS dependencies with Bun when required
   using `bun install --ignore-scripts` because grammar generation only needs package resolution, not native Node addon build hooks
4. run `tree-sitter generate` for every grammar on every build
5. compile generated `parser.c` plus optional `scanner.c` or `scanner.cc` with Zig
6. build a local static grammar registry archive
7. compile the final Go binary with `cgo` against that local archive

This keeps the release binary self-contained while avoiding pre-generated grammar artifacts checked into the project.

## Tool bootstrap

`build.bat` currently bootstraps:

- Go `1.26.2`
- Zig `0.15.2`
- Bun `1.3.11`
- `msvcup` with `msvc-14.44.17.14` and `sdk-10.0.22621.7`
- rustup/cargo
- `tree-sitter-cli` built with `--no-default-features` and driven through Bun

`build.sh` bootstraps the same toolchain set for Linux.

Portable tool state is stored under:

- `build_cache/toolchains/`
- `build_cache/cargo/`
- `build_cache/rustup/`
- `build_cache/tools/`
- `build_cache/grammars/`
- `build_cache/generated/`

## Grammar manifest

Grammar repository selections live in [`GRAMMARS.txt`](C:/Users/Michele/Desktop/ceretree/GRAMMARS.txt).

Each line is:

```text
language|repo_url|revision|subdirectory|needs_bun
```

Meaning:

- `language`: RPC language id and generated registry key
- `repo_url`: grammar repository
- `revision`: git revision fetched during build, typically `HEAD` in the current floating setup
- `subdirectory`: grammar root inside the repository, `.` when the repo root is the grammar root
- `needs_bun`: `1` when the grammar repo needs JS package installation before `tree-sitter generate`

The current manifest intentionally uses floating `HEAD` revisions. This keeps grammar updates automatic, but it also means builds are not fully reproducible across different dates.

## Build

Windows:

```bat
build.bat
```

Linux:

```sh
./build.sh
```

## Tests

Windows:

```bat
test.bat
```

Linux:

```sh
./test.sh
```

The black-box tests exercise:

- `system.describe`
- `roots.add`
- `query` on `src/main.go`

On Windows, Rust is bootstrapped against a standalone MSVC environment installed in `build_cache/msvc` through `msvcup`, while Zig remains the compiler used for grammar object generation and Go `cgo`.

The local `tree-sitter-cli` install intentionally disables the optional native QuickJS runtime. Every grammar regeneration step runs `tree-sitter generate --js-runtime <bun>`, so parser generation still works without the extra `libclang` dependency chain that the native QuickJS feature would pull into the Windows bootstrap.

## JSON-RPC methods

`system.describe`

Returns executable metadata, cache location, supported languages, and currently implemented methods.

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
    "exclude":"**/vendor/**"
  }
}
```

The `query` method parses every matching file under the selected roots and returns the captured nodes with byte offsets, points, kinds, and captured text.
