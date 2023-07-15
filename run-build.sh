#! /usr/bin/env bash
set -e 

PREV_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]:-$0}")" || { echo >&2 "Failed to cd to script's directory"; return 1; }

DIR='./build'

rm -r "$DIR"
mkdir "$DIR"

# lib
LIB="lib"
mkdir "$DIR/$LIB"
find "./$LIB" -type f -name "*.sh" | while read -r file; do
    cp "$file" "$DIR/$LIB/"
done

# scripts
find . -maxdepth 1 -type f ! -name "run-*.sh" ! -name "test.sh" -name "*.sh" | while read -r file; do
    cp "$file" "$DIR/"
done

cd "$PREV_DIR"