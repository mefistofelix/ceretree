#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
EXE="$ROOT/bin/ceretree"
BUN_BIN="$ROOT/build_cache/toolchains/bun-linux-x64/bun"

[ -x "$EXE" ] || exit 1
[ -x "$BUN_BIN" ] || exit 1

DESCRIBE_JSON="$("$EXE" '{"jsonrpc":"2.0","id":1,"method":"system.describe"}')"
printf '%s' "$DESCRIBE_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (data.result.name !== 'ceretree') process.exit(1); if (!data.result.languages.includes('go')) process.exit(1);"

ADD_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"roots.add\",\"params\":{\"paths\":[\"$ROOT\"]}}")"
printf '%s' "$ADD_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1);"

QUERY_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"query\",\"params\":{\"language\":\"go\",\"query\":\"(package_identifier) @name\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\"}}")"
printf '%s' "$QUERY_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (!Array.isArray(data.result.matches) || data.result.matches.length < 1) process.exit(1);"

INDEX_JSON="$("$EXE" '{"jsonrpc":"2.0","id":4,"method":"index.status"}')"
printf '%s' "$INDEX_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (!Array.isArray(data.result.roots) || data.result.roots.length < 1) process.exit(1); if (!data.result.last_query) process.exit(1);"

SYMBOLS_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"symbols.overview\",\"params\":{\"language\":\"go\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\",\"max_symbols\":20}}")"
printf '%s' "$SYMBOLS_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (!Array.isArray(data.result.files) || data.result.files.length < 1) process.exit(1); if (!Array.isArray(data.result.files[0].symbols) || data.result.files[0].symbols.length < 1) process.exit(1);"

FIND_SYMBOLS_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"symbols.find\",\"params\":{\"language\":\"go\",\"name\":\"handle_query\",\"kinds\":[\"function\"],\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\"}}")"
printf '%s' "$FIND_SYMBOLS_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); const symbols = data.result.files.flatMap(file => file.symbols); if (!symbols.some(symbol => symbol.name === 'handle_query')) process.exit(1);"

PAGE_SYMBOLS_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":61,\"method\":\"symbols.find\",\"params\":{\"language\":\"go\",\"kinds\":[\"function\"],\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\",\"limit\":1,\"offset\":1}}")"
printf '%s' "$PAGE_SYMBOLS_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (data.result.summary.limit !== 1) process.exit(1); if (data.result.summary.offset !== 1) process.exit(1); if (data.result.summary.files_returned > 1) process.exit(1);"

CALLS_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"calls.find\",\"params\":{\"language\":\"go\",\"callee\":\"invalid_params\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\"}}")"
printf '%s' "$CALLS_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); const calls = data.result.files.flatMap(file => file.calls); if (!calls.some(call => call.callee === 'invalid_params')) process.exit(1);"

PAGE_CALLS_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"calls.find\",\"params\":{\"language\":\"go\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\",\"limit\":1}}")"
printf '%s' "$PAGE_CALLS_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (data.result.summary.limit !== 1) process.exit(1); if (data.result.summary.files_returned > 1) process.exit(1);"

COMMON_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"query.common\",\"params\":{\"language\":\"go\",\"preset\":\"functions.by_name\",\"name\":\"handle_query\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\"}}")"
printf '%s' "$COMMON_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); const symbols = data.result.files.flatMap(file => file.symbols); if (!symbols.some(symbol => symbol.name === 'handle_query')) process.exit(1);"

PAGE_QUERY_JSON="$("$EXE" "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"query\",\"params\":{\"language\":\"go\",\"query\":\"(identifier) @name\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\",\"limit\":1}}")"
printf '%s' "$PAGE_QUERY_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const data = JSON.parse(fs.readFileSync(0, 'utf8')); if (data.result.summary.limit !== 1) process.exit(1); if (data.result.summary.files_returned > 1) process.exit(1);"

SERVER_JSON="$(printf '%s\n%s\n' '{"jsonrpc":"2.0","id":9,"method":"system.describe"}' "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"symbols.overview\",\"params\":{\"language\":\"go\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\",\"max_symbols\":5}}" | "$EXE" --server)"
printf '%s' "$SERVER_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const lines = fs.readFileSync(0, 'utf8').trim().split(/\r?\n/).filter(Boolean); if (lines.length !== 2) process.exit(1); const first = JSON.parse(lines[0]); const second = JSON.parse(lines[1]); if (!first.result.server_mode.active) process.exit(1); if (!Array.isArray(second.result.files) || second.result.files.length < 1) process.exit(1);"

BOM_SERVER_JSON="$("$BUN_BIN" -e "const body = '{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"system.describe\"}\n{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"index.status\"}\n'; process.stdout.write(Buffer.concat([Buffer.from([0xEF,0xBB,0xBF]), Buffer.from(body, 'utf8')]));" | "$EXE" --server)"
printf '%s' "$BOM_SERVER_JSON" | "$BUN_BIN" -e "const fs = require('node:fs'); const lines = fs.readFileSync(0, 'utf8').trim().split(/\r?\n/).filter(Boolean); if (lines.length !== 2) process.exit(1); const first = JSON.parse(lines[0]); const second = JSON.parse(lines[1]); if (first.id !== 11 || first.result.name !== 'ceretree') process.exit(1); if (second.id !== 12 || !Array.isArray(second.result.roots)) process.exit(1);"
