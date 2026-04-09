#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GO_VERSION="1.26.2"
ZIG_VERSION="0.15.2"
BUN_VERSION="bun-v1.3.11"
GO_DIR="$ROOT/build_cache/toolchains/go"
GO_BIN="$GO_DIR/bin/go"
GO_ARCHIVE="$ROOT/build_cache/downloads/go${GO_VERSION}.linux-amd64.tar.gz"
ZIG_DIR="$ROOT/build_cache/toolchains/zig-linux-x86_64-$ZIG_VERSION"
ZIG_BIN="$ZIG_DIR/zig"
ZIG_ARCHIVE="$ROOT/build_cache/downloads/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
BUN_DIR="$ROOT/build_cache/toolchains/bun-linux-x64-$BUN_VERSION"
BUN_BIN="$BUN_DIR/bun"
BUN_ARCHIVE="$ROOT/build_cache/downloads/bun-linux-x64-$BUN_VERSION.zip"
RUSTUP_HOME="$ROOT/build_cache/rustup"
CARGO_HOME="$ROOT/build_cache/cargo"
RUSTUP_INIT="$ROOT/build_cache/downloads/rustup-init.sh"
TARGET_TRIPLE="x86_64-unknown-linux-gnu"
WRAPPER_DIR="$ROOT/build_cache/tool_wrappers"
GEN_DIR="$ROOT/build_cache/generated"
OBJ_DIR="$GEN_DIR/obj"
INC_DIR="$GEN_DIR/include"
SRC_DIR="$GEN_DIR/src"
LIB_DIR="$GEN_DIR/lib"
GRAMMAR_ROOT="$ROOT/build_cache/grammars"
TREE_SITTER_BIN="$ROOT/build_cache/tools/tree-sitter-cli/bin/tree-sitter"

mkdir -p "$ROOT/build_cache/downloads" "$ROOT/build_cache/toolchains" "$ROOT/bin" "$ROOT/build_cache/gopath" "$ROOT/build_cache/gocache" "$WRAPPER_DIR" "$OBJ_DIR" "$INC_DIR" "$SRC_DIR" "$LIB_DIR" "$GRAMMAR_ROOT"

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

if [ ! -x "$CARGO_HOME/bin/rustup" ]; then
  curl -fsSL https://sh.rustup.rs -o "$RUSTUP_INIT"
  chmod +x "$RUSTUP_INIT"
  env RUSTUP_HOME="$RUSTUP_HOME" CARGO_HOME="$CARGO_HOME" sh "$RUSTUP_INIT" -y --profile minimal --default-toolchain none --no-modify-path
fi

cat >"$WRAPPER_DIR/zig-cc.sh" <<EOF
#!/usr/bin/env sh
exec "$ZIG_BIN" cc -target $TARGET_TRIPLE "\$@"
EOF
chmod +x "$WRAPPER_DIR/zig-cc.sh"

cat >"$WRAPPER_DIR/zig-cxx.sh" <<EOF
#!/usr/bin/env sh
exec "$ZIG_BIN" c++ -target $TARGET_TRIPLE "\$@"
EOF
chmod +x "$WRAPPER_DIR/zig-cxx.sh"

export GOROOT="$GO_DIR"
export GOPATH="$ROOT/build_cache/gopath"
export GOCACHE="$ROOT/build_cache/gocache"
export RUSTUP_HOME
export CARGO_HOME
export PATH="$GOROOT/bin:$BUN_DIR:$CARGO_HOME/bin:$PATH"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$WRAPPER_DIR/zig-cc.sh"
export CC="$WRAPPER_DIR/zig-cc.sh"
export CXX="$WRAPPER_DIR/zig-cxx.sh"
export CGO_ENABLED=1

if ! rustup toolchain list | grep -q "$TARGET_TRIPLE"; then
  rustup toolchain install "stable-$TARGET_TRIPLE" --profile minimal
fi
rustup default "stable-$TARGET_TRIPLE"

if [ ! -x "$TREE_SITTER_BIN" ]; then
  cargo install --locked tree-sitter-cli --root "$ROOT/build_cache/tools/tree-sitter-cli"
fi

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
  if [ ! -d "$repo_dir/.git" ]; then
    rm -rf "$repo_dir"
    git clone --filter=blob:none --no-checkout "$repo" "$repo_dir"
  fi
  git -C "$repo_dir" fetch --depth 1 origin "$revision"
  git -C "$repo_dir" checkout --force "$revision"

  grammar_dir="$repo_dir"
  if [ "$location" != "." ]; then
    grammar_dir="$repo_dir/$location"
  fi

  if [ "$needs_npm" = "1" ] && [ -f "$grammar_dir/package.json" ]; then
    (cd "$grammar_dir" && "$BUN_BIN" install)
  fi

  (cd "$grammar_dir" && "$TREE_SITTER_BIN" generate --js-runtime "$BUN_BIN")

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
done <"$ROOT/GRAMMARS.txt"

cat >>"$SRC_DIR/ceretree_grammars.c" <<'EOF'
const TSLanguage *ceretree_language(const char *name) {
EOF

while IFS='|' read -r language _rest; do
  [ -n "$language" ] || continue
  cat >>"$SRC_DIR/ceretree_grammars.c" <<EOF
  if (strcmp(name, "$language") == 0) return tree_sitter_${language}();
EOF
done <"$ROOT/GRAMMARS.txt"

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
