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
2. fetch pinned grammar repositories from `GRAMMARS.txt`
3. install grammar-local JS dependencies with Bun when required
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
- rustup/cargo
- `tree-sitter-cli`

`build.sh` bootstraps the same toolchain set for Linux.

Portable tool state is stored under:

- `build_cache/toolchains/`
- `build_cache/cargo/`
- `build_cache/rustup/`
- `build_cache/tools/`
- `build_cache/grammars/`
- `build_cache/generated/`

## Grammar manifest

Pinned grammar repositories live in [`GRAMMARS.txt`](C:/Users/Michele/Desktop/ceretree/GRAMMARS.txt).

Each line is:

```text
language|repo_url|commit|subdirectory|needs_bun
```

Meaning:

- `language`: RPC language id and generated registry key
- `repo_url`: grammar repository
- `commit`: pinned revision fetched during build
- `subdirectory`: grammar root inside the repository, `.` when the repo root is the grammar root
- `needs_bun`: `1` when the grammar repo needs JS package installation before `tree-sitter generate`

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

## Current Windows status

The current Windows bootstrap is documented but not yet passing end-to-end.

The current failure happens while Cargo tries to compile `tree-sitter-cli` with the Rust GNU Windows target through the Zig linker wrapper. The observed errors are:

- missing `msvcrt`
- missing `dlltool.exe`

So the Windows build pipeline is implemented and reproducible up to that exact failure point, but it is not yet fully working.

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
