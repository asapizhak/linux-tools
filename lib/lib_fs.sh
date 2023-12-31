#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# less external command calls here, more pure bash!
# function prefix: fs
# Functions that work with file system, files, devices, dirs, etc here.
###############################################################################

#
#    object
#    out_obj_size
function getStorageObjectSize {
    coreEnsureCommands du blockdev
    declare -r object="$1"
    declare -n out_obj_size=$2

    [[ ! -r "$object" ]] && coreFailExit "Object '$object' is unreadable."

    if [[ -f "$object" || -d "$object" ]]; then
        size="$(du --bytes --summarize "$object" | awk '{print $1}')"
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
    coreEnsureCommands find
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

#
#    file
#    out_usage[] ('device', 'free')
function fsGetDiskSpaceUsage {
    coreEnsureCommands df awk
    declare -r file="$1"
    declare -n out_usage=$2

    declare raw
    raw="$(df -PB 1 --sync "$file")"

    out_usage['device']="$(awk 'NR==2 {print $1}' <<< "$raw")"
    # shellcheck disable=SC2034
    out_usage['free']="$(awk 'NR==2 {print $4}' <<< "$raw")"
}

#
#    path  -  path where to look for free space
#    expected_size in bytes
#    out_free_space_diff - if this is 0 or positive, free space is enough by absolute value.
#                          If it's negative then not enough free space by the amount of absolute value.
function fsIsEnoughFreeSpace {
    declare -r path=$1
    declare -r expected_size=$2
    declare -n out_free_space_diff=$3

    if [[ $expected_size -lt 0 ]]; then
        echo2 "Expected size wrong, got $expected_size"
        return 1
    fi

    declare -A usage=()
    fsGetDiskSpaceUsage "$path" usage

    declare -ri free_space="${usage['free']}"

    # shellcheck disable=SC2034
    out_free_space_diff=$((free_space-expected_size))
}

#
function fsIsLoopDevice {
    coreEnsureCommands lsblk head

    declare dev_type; dev_type="$(lsblk -no TYPE "$1")"
    dev_type="$(head -n 1 <<< "$dev_type")"

    [[ $dev_type = "loop" ]]
}

function fsIsBlockDeviceFile {
    declare -r _file="$1"
    declare -n out_is_mountable=$2

    declare info status
    set +e
    info="$(blkid --probe --output export "$_file")"
    status=$?
    set -e

    if [[ $status -eq 2 ]]; then
        out_is_mountable=0
        return 0
    elif [[ $status -ne 0 ]]; then
        out_is_mountable=0
        return $status
    fi

    declare -A data=()
    declare key value
    while IFS='=' read -r key value; do
        data["$key"]="$value"
    done <<< "$info"

    #shellcheck disable=SC2034
    out_is_mountable=1
    F_COLOR=gray echo2 "$(basename "$_file"): USAGE=${data['USAGE']:-}; TYPE=${data['TYPE']:-}; PTTYPE=${data['PTTYPE']:-}"
}

# Returns key-value array with device info, or empty array if input is not block device.
#   input_object
#   out_attrs ('TYPE', 'USAGE', 'DEVNAME', etc)
#   out_attrs_found  --  1 if attributes found, 0 if not (basically tells if object can be identified and mountedas block device)
function fsGetBlockDeviceAttrs {
    coreEnsureCommands blkid
    declare -r _input_object="$1"
    if [[ -n ${2:-} ]]; then declare -n out_attrs=$2; else declare -A out_attrs=(); fi
    if [[ -n ${3:-} ]]; then declare -n out_attrs_found=$3; else declare -i out_attrs_found=0; fi

    set +e
    declare info_raw; info_raw="$( \
        blkid --probe --output export "$_input_object"; \
        declare c=$?; if [[ $c -eq 0 || $c -eq 2 ]]; then return 0; else return $c; fi; \
    )"
    declare -r status=$?
    set -e

    if [[ $status -eq 2 ]]; then # Not a block device or no info found
        out_attrs=()
        out_attrs_found=0
        return 0

    elif [[ $status -ne 0 ]]; then
        out_attrs=()
        out_attrs_found=0
        return $status
    fi

    out_attrs_found=1

    out_attrs=()
    while IFS='=' read -r key value; do
        # shellcheck disable=SC2034
        [[ -n $key ]] && out_attrs["$key"]="$value"
    done <<< "$info_raw"

    # sometimes status code is ok but output is empty
    if [[ ${#out_attrs[@]} -lt 1 ]]; then
        # shellcheck disable=SC2034
        out_attrs_found=0
    fi
}

function fsIsLuksContainer {
    declare -r _input_object="$1"

    declare -A _obj_attrs
    fsGetBlockDeviceAttrs "$_input_object" _obj_attrs

    [[ ${_obj_attrs['TYPE']:-} == "crypto_LUKS" ]]
}

function fsIsSqfsContainer {
    declare -r _input_object="$1"

     declare -A _obj_attrs
    fsGetBlockDeviceAttrs "$_input_object" _obj_attrs

    [[ ${_obj_attrs['TYPE']:-} == "squashfs" ]]
}
