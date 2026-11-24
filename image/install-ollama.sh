#!/bin/sh
# Install a pinned Ollama release for linux-amd64 and check its sha256 before use.
set -eu
VERSION=v0.40.13
SHA256=c9490e0f520be21271d969e6703f012268b1d39f8b70dd58854e5bfef7a75bb6
DEST=${OLLAMA_HOME_DIR:-$HOME/.local/ollama}
TARBALL=${OLLAMA_TARBALL:-$HOME/.cache/ollama-$VERSION-linux-amd64.tar.zst}

mkdir -p "$(dirname "$TARBALL")" "$DEST"
if [ ! -f "$TARBALL" ]; then
  curl -fsSL -o "$TARBALL" "https://github.com/ollama/ollama/releases/download/$VERSION/ollama-linux-amd64.tar.zst"
fi
echo "$SHA256  $TARBALL" | sha256sum -c -
tar --zstd -xf "$TARBALL" -C "$DEST"

# Pin the CPU backend. Ollama ships one CPU library per instruction set (haswell, icelake,
# zen4, sapphirerapids, ...) and loads the best one for the machine. Different libraries
# give different text for the same seed (workflow `backend`, run 44168997126), so keep only
# the AVX2 build, which every x86-64 CI runner can run.
# OLLAMA_CPU_BACKEND=all keeps every library (used only by the `backend` experiment).
BACKEND=${OLLAMA_CPU_BACKEND:-haswell}
LIB="$DEST/lib/ollama"
if [ "$BACKEND" != all ]; then
  [ -f "$LIB/libggml-cpu-$BACKEND.so" ] || { echo "no CPU backend $BACKEND in $LIB" >&2; exit 1; }
  mkdir -p "$DEST/unused-backends"
  for f in "$LIB"/libggml-cpu-*.so; do
    [ "$(basename "$f")" = "libggml-cpu-$BACKEND.so" ] || mv "$f" "$DEST/unused-backends/"
  done
  echo "CPU backend pinned to $BACKEND"
fi
"$DEST/bin/ollama" --version || true
