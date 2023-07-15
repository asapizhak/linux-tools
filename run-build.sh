#! /usr/bin/env bash
set -e 

PREV_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]:-$0}")" || { echo >&2 "Failed to cd to script's directory"; return 1; }

DIR='./build'

rm -r "$DIR" && echo >&2 "Build: Removed previous directory $DIR"
mkdir "$DIR"

# lib
LIB="lib"
mkdir "$DIR/$LIB"
find "./$LIB" -type f -name "*.sh" | while read -r file; do
    cp "$file" "$DIR/$LIB/" && echo >&2 "Build: $file copied"
done
echo >&2 "Build: Lib dir finished"

# scripts
find . -maxdepth 1 -type f ! -name "run-*.sh" ! -name "test.sh" -name "*.sh" | while read -r file; do
    cp "$file" "$DIR/" && echo >&2 "Build: $file copied"
done
echo >&2 "Build: Done."
cd "$PREV_DIR"
