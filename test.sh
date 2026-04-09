#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

"$ROOT/build.sh"

DESCRIBE_JSON="$("$ROOT/bin/ceretree" '{"jsonrpc":"2.0","id":1,"method":"system.describe"}')"
printf '%s' "$DESCRIBE_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["result"]["name"]=="ceretree"; assert "go" in data["result"]["languages"]'

ADD_JSON="$("$ROOT/bin/ceretree" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"roots.add\",\"params\":{\"paths\":[\"$ROOT\"]}}")"
printf '%s' "$ADD_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert len(data["result"]["roots"]) >= 1'

QUERY_JSON="$("$ROOT/bin/ceretree" "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"query\",\"params\":{\"language\":\"go\",\"query\":\"(package_identifier) @name\",\"roots\":[\"$ROOT\"],\"include\":\"src/main.go\"}}")"
printf '%s' "$QUERY_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert len(data["result"]["matches"]) >= 1'
