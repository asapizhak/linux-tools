#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

ensureCommands stat blockdev

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

    [[ ! -r "$object" ]] && fail "Object '$object' is unreadable."

    if [[ -f "$object" ]]; then
        size=$(stat -c "%s" "$object")
    elif [[ -b "$object" ]]; then
        size=$(blockdev --getsize64 "$object")
    else
        fail "Failed to get size: '$object' is not a file, nor a block device."
    fi

    # shellcheck disable=SC2034
    printf -v out_obj_size "%d" "$size"
}
