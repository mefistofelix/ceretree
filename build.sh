#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GO_VERSION="1.26.2"
ZIG_VERSION="0.15.2"
BUN_VERSION="bun-v1.3.11"
TREE_SITTER_VERSION="v0.26.8"
GO_DIR="$ROOT/build_cache/toolchains/go"
GO_BIN="$GO_DIR/bin/go"
GO_ARCHIVE="$ROOT/build_cache/downloads/go${GO_VERSION}.linux-amd64.tar.gz"
ZIG_DIR="$ROOT/build_cache/toolchains/zig-linux-x86_64-$ZIG_VERSION"
ZIG_BIN="$ZIG_DIR/zig"
ZIG_ARCHIVE="$ROOT/build_cache/downloads/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
BUN_DIR="$ROOT/build_cache/toolchains/bun-linux-x64-$BUN_VERSION"
BUN_BIN="$BUN_DIR/bun"
BUN_ARCHIVE="$ROOT/build_cache/downloads/bun-linux-x64-$BUN_VERSION.zip"
WRAPPER_DIR="$ROOT/build_cache/tool_wrappers"
GRAMMAR_STATE_DIR="$ROOT/build_cache/grammar_state"
GEN_DIR="$ROOT/build_cache/generated"
OBJ_DIR="$GEN_DIR/obj"
INC_DIR="$GEN_DIR/include"
SRC_DIR="$GEN_DIR/src"
LIB_DIR="$GEN_DIR/lib"
GRAMMAR_ROOT="$ROOT/build_cache/grammars"
TREE_SITTER_BIN="$ROOT/build_cache/tools/tree-sitter-cli/bin/tree-sitter"
TREE_SITTER_ARCHIVE="$ROOT/build_cache/downloads/tree-sitter-cli-linux-x64.zip"

mkdir -p "$ROOT/build_cache/downloads" "$ROOT/build_cache/toolchains" "$ROOT/bin" "$ROOT/build_cache/gopath" "$ROOT/build_cache/gocache" "$WRAPPER_DIR" "$GRAMMAR_STATE_DIR" "$OBJ_DIR" "$INC_DIR" "$SRC_DIR" "$LIB_DIR" "$GRAMMAR_ROOT"

if [ ! -x "$GO_BIN" ]; then
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o "$GO_ARCHIVE"
  rm -rf "$GO_DIR"
  tar -C "$ROOT/build_cache/toolchains" -xzf "$GO_ARCHIVE"
fi

if [ ! -x "$ZIG_BIN" ]; then
  curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" -o "$ZIG_ARCHIVE"
  rm -rf "$ZIG_DIR"
  tar -C "$ROOT/build_cache/toolchains" -xJf "$ZIG_ARCHIVE"
  mv "$ROOT/build_cache/toolchains/zig-x86_64-linux-$ZIG_VERSION" "$ZIG_DIR"
fi

if [ ! -x "$BUN_BIN" ]; then
  curl -fsSL "https://github.com/oven-sh/bun/releases/download/$BUN_VERSION/bun-linux-x64.zip" -o "$BUN_ARCHIVE"
  rm -rf "$BUN_DIR"
  unzip -qo "$BUN_ARCHIVE" -d "$ROOT/build_cache/toolchains"
fi

if [ ! -x "$TREE_SITTER_BIN" ]; then
  curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/$TREE_SITTER_VERSION/tree-sitter-cli-linux-x64.zip" -o "$TREE_SITTER_ARCHIVE"
  rm -rf "$ROOT/build_cache/tools/tree-sitter-cli"
  mkdir -p "$ROOT/build_cache/tools/tree-sitter-cli/bin"
  unzip -qo "$TREE_SITTER_ARCHIVE" -d "$ROOT/build_cache/tools/tree-sitter-cli/bin"
  chmod +x "$TREE_SITTER_BIN"
fi

cat >"$WRAPPER_DIR/zig-cc.sh" <<EOF
#!/usr/bin/env sh
exec "$ZIG_BIN" cc -target x86_64-linux-gnu "\$@"
EOF
chmod +x "$WRAPPER_DIR/zig-cc.sh"

cat >"$WRAPPER_DIR/zig-cxx.sh" <<EOF
#!/usr/bin/env sh
exec "$ZIG_BIN" c++ -target x86_64-linux-gnu "\$@"
EOF
chmod +x "$WRAPPER_DIR/zig-cxx.sh"

export GOROOT="$GO_DIR"
export GOPATH="$ROOT/build_cache/gopath"
export GOCACHE="$ROOT/build_cache/gocache"
export PATH="$GOROOT/bin:$BUN_DIR:$PATH"
export CC="$WRAPPER_DIR/zig-cc.sh"
export CXX="$WRAPPER_DIR/zig-cxx.sh"
export CGO_ENABLED=1

rm -f "$OBJ_DIR"/* "$SRC_DIR"/ceretree_grammars.c "$INC_DIR"/ceretree_grammars.h "$LIB_DIR"/libceretree_grammars.a

cat >"$INC_DIR/ceretree_grammars.h" <<'EOF'
typedef struct TSLanguage TSLanguage;
const TSLanguage *ceretree_language(const char *name);
EOF

cat >"$SRC_DIR/ceretree_grammars.c" <<'EOF'
#include <string.h>
#include "ceretree_grammars.h"
EOF

while IFS='|' read -r language repo revision location needs_npm; do
  [ -n "$language" ] || continue
  repo_dir="$GRAMMAR_ROOT/$language/repo"
  state_dir="$GRAMMAR_STATE_DIR/$language"
  fetch_stamp="$state_dir/fetch.txt"
  root_bun_stamp="$state_dir/root_bun.txt"
  grammar_bun_stamp="$state_dir/grammar_bun.txt"
  generate_stamp="$state_dir/generate.txt"
  archive_zip="$ROOT/build_cache/downloads/grammar_${language}.zip"
  archive_tmp="$GRAMMAR_ROOT/$language/archive_tmp"
  repo_slug="${repo#https://github.com/}"
  repo_slug="${repo_slug%/}"
  resolved_revision="$revision"
  mkdir -p "$state_dir"

  if [ "$revision" = "HEAD" ]; then
    default_branch="$(curl -fsSL "https://api.github.com/repos/$repo_slug" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$default_branch" ] || exit 1
    resolved_revision="$(curl -fsSL "https://api.github.com/repos/$repo_slug/commits/$default_branch" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1)"
  else
    resolved_revision="$(curl -fsSL "https://api.github.com/repos/$repo_slug/commits/$revision" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1)"
  fi
  [ -n "$resolved_revision" ] || exit 1

  if [ ! -f "$fetch_stamp" ] || [ "$(cat "$fetch_stamp")" != "$resolved_revision" ] || [ ! -d "$repo_dir" ]; then
    rm -rf "$archive_tmp" "$repo_dir"
    mkdir -p "$archive_tmp"
    curl -fsSL "https://github.com/$repo_slug/archive/$resolved_revision.zip" -o "$archive_zip"
    unzip -qo "$archive_zip" -d "$archive_tmp"
    extracted_dir="$(find "$archive_tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$extracted_dir" ] || exit 1
    mv "$extracted_dir" "$repo_dir"
    rm -rf "$archive_tmp"
    printf '%s' "$resolved_revision" >"$fetch_stamp"
  fi

  grammar_dir="$repo_dir"
  if [ "$location" != "." ]; then
    grammar_dir="$repo_dir/$location"
  fi
  generate_key="$resolved_revision|$TREE_SITTER_VERSION|$location|$needs_npm"

  if [ "$needs_npm" = "1" ] && [ -f "$grammar_dir/package.json" ]; then
    if [ ! -f "$grammar_bun_stamp" ] || [ "$(cat "$grammar_bun_stamp")" != "$generate_key" ]; then
      (cd "$grammar_dir" && "$BUN_BIN" install --ignore-scripts)
      printf '%s' "$generate_key" >"$grammar_bun_stamp"
    fi
  fi

  if [ "$needs_npm" = "1" ] && [ -f "$repo_dir/package.json" ]; then
    if [ ! -f "$root_bun_stamp" ] || [ "$(cat "$root_bun_stamp")" != "$generate_key" ]; then
      (cd "$repo_dir" && "$BUN_BIN" install --ignore-scripts)
      printf '%s' "$generate_key" >"$root_bun_stamp"
    fi
  fi

  if [ ! -f "$generate_stamp" ] || [ ! -f "$grammar_dir/src/parser.c" ] || [ "$(cat "$generate_stamp")" != "$generate_key" ]; then
    (cd "$grammar_dir" && "$TREE_SITTER_BIN" generate --js-runtime bun)
    printf '%s' "$generate_key" >"$generate_stamp"
  fi

  parser_file="$grammar_dir/src/parser.c"
  if [ ! -f "$parser_file" ]; then
    echo "missing generated parser for $language" >&2
    exit 1
  fi

  cat >>"$SRC_DIR/ceretree_grammars.c" <<EOF
extern const TSLanguage *tree_sitter_${language}(void);
EOF

  parser_obj="$OBJ_DIR/${language}_parser.o"
  "$WRAPPER_DIR/zig-cc.sh" -c -O2 -I"$grammar_dir/src" "$parser_file" -o "$parser_obj"

  if [ -f "$grammar_dir/src/scanner.c" ]; then
    "$WRAPPER_DIR/zig-cc.sh" -c -O2 -I"$grammar_dir/src" "$grammar_dir/src/scanner.c" -o "$OBJ_DIR/${language}_scanner.o"
  fi
  if [ -f "$grammar_dir/src/scanner.cc" ]; then
    "$WRAPPER_DIR/zig-cxx.sh" -c -O2 -I"$grammar_dir/src" "$grammar_dir/src/scanner.cc" -o "$OBJ_DIR/${language}_scanner_cc.o"
  fi
done <"$ROOT/src/GRAMMARS.txt"

cat >>"$SRC_DIR/ceretree_grammars.c" <<'EOF'
const TSLanguage *ceretree_language(const char *name) {
EOF

while IFS='|' read -r language _rest; do
  [ -n "$language" ] || continue
  cat >>"$SRC_DIR/ceretree_grammars.c" <<EOF
  if (strcmp(name, "$language") == 0) return tree_sitter_${language}();
EOF
done <"$ROOT/src/GRAMMARS.txt"

cat >>"$SRC_DIR/ceretree_grammars.c" <<'EOF'
  return 0;
}
EOF

"$WRAPPER_DIR/zig-cc.sh" -c -O2 -I"$INC_DIR" "$SRC_DIR/ceretree_grammars.c" -o "$OBJ_DIR/ceretree_grammars.o"
"$ZIG_BIN" ar rcs "$LIB_DIR/libceretree_grammars.a" "$OBJ_DIR"/*.o

"$GOROOT/bin/gofmt" -w "$ROOT/src/main.go"

export CGO_CFLAGS="-I$INC_DIR"
export CGO_LDFLAGS="$LIB_DIR/libceretree_grammars.a"

"$GO_BIN" build -o "$ROOT/bin/ceretree" ./src
