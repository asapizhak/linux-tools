#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

coreEnsureCommands stat blockdev

###############################################################################
# less external command calls here, more pure bash!
# function prefix: fs
# Functions that work with file system, files, devices, dirs, etc here.
###############################################################################

#
#    object
#    out_obj_size
function getStorageObjectSize {
    declare -r object="$1"
    declare -n out_obj_size=$2

    [[ ! -r "$object" ]] && coreFailExit "Object '$object' is unreadable."

    if [[ -f "$object" ]]; then
        size=$(stat -c "%s" "$object")
    elif [[ -b "$object" ]]; then
        size=$(blockdev --getsize64 "$object")
    else
        coreFailExit "Failed to get size: '$object' is not a file, nor a block device."
    fi

    # shellcheck disable=SC2034
    printf -v out_obj_size "%d" "$size"
}

#
#    directory
function fsDirectoryHasContent {
    declare -r directory=$1

    if [[ -n "$(find "$directory" -mindepth 1 -print -quit)" ]]; then
        return 0
    else 
        return 1
    fi
}

#
#    out_combined
function fsJoinPaths {
    declare -n out_combined=$1; shift

    [[ -z "$out_combined" ]] && { out_combined="${1:-}"; shift; }

    for path in "$@"; do
        if [[ "$path" == /* ]]; then
            F_COLOR='red' echo2 "Cannot join absolute path '$path'"
            return 1
        fi
        out_combined="${out_combined%/}/$path"
    done
}
