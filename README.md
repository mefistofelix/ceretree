# ceretree

`ceretree` is a JSON-RPC CLI for recursive source-tree inspection built in Go on top of `github.com/tree-sitter/go-tree-sitter`.

This implementation slice provides:

- one-shot CLI execution through a raw JSON-RPC request passed as the first argument or through stdin
- persistent root registration in `bin/.ceretree-cache/state.json`
- recursive file discovery with relative include and exclude globs supporting `**`
- statically linked Tree-sitter grammars compiled into the final binary
- build-time grammar regeneration on every build through `tree-sitter-cli`
- portable bootstrap of Go, Zig, rustup/cargo, Bun, and `tree-sitter-cli` under `build_cache/`

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

## Build

Windows:

```bat
build.bat
```

Linux:

```sh
./build.sh
```

Both entrypoints always regenerate the grammar C sources before compiling the binary.

## Test

Windows:

```bat
test.bat
```

Linux:

```sh
./test.sh
```

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
