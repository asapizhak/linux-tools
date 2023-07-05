#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# less external command calls here, more pure bash!
# function prefix: fs
# Functions that work with file system, files, devices, dirs, etc here.
###############################################################################

# Replace $1 with last valid argument number for the function.
# [[ "$1" == "${!#}" ]] && fail "Missing last argument."

ensureCommands stat blockdev

function getStorageObjectSize {
    object="$1"
    [[ "$1" == "${!#}" ]] && fail "Missing last argument."

    [[ ! -r "$object" ]] && fail "Object '$object' is unreadable."

    if [[ -f "$object" ]]; then
        size=$(stat -c "%s" "$object")
    elif [[ -b "$object" ]]; then
        size=$(blockdev --getsize64 "$object")
    else
        fail "Failed to get size: '$object' is not a file, nor a block device."
    fi

    printf -v ${!#} "%d" "$size"
}
