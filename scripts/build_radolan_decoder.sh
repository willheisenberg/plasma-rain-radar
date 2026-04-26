#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: build_radolan_decoder.sh <output-binary>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/decode_radolan.cpp"
OUT="$1"

mkdir -p "$(dirname "$OUT")"
g++ -std=c++20 -O2 "$SRC" -o "$OUT"
