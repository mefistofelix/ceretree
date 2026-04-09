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
