#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# no external command calls here, only pure bash!
# function prefix: str
# Functions that work with strings here.
###############################################################################

function strPadString {
    declare -r str="$1"
    declare -i max="${2:-0}"
    declare -n f_out=${3}

    max=$((max))
    declare -i max_sign
    [[ $max -ge 0 ]] && max_sign=1 || max_sign=-1
    max=$((max * max_sign)) # remove sign from max

    declare -ri strlen=${#str}
    [[ $max -lt $strlen ]] && max=$strlen

    max=$((max * max_sign)) # put max sign back

    # shellcheck disable=SC2034
    printf -v f_out "%$max.${max#-}s" "$str"
}

function strIsPositiveIntString {
    declare -r str=$1
    [[ $str =~ ^[0-9]+$ ]] && return 0 || return 1
}
