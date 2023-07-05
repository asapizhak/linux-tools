#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# no external command calls here, only pure bash!
# function prefix: str
# Functions that work with strings here.
###############################################################################

# Replace $1 with last valid argument number for the function.
# [[ "$1" == "${!#}" ]] && fail "Missing last argument."

function padStr {
    str=$1
    max=${2:-0}
    [[ "$2" == "${!#}" ]] && fail "Missing last argument."

    [[ ${#str} -gt $((max)) ]] && max=${#str}
    printf -v ${!#} "%$max.${max#-}s" "$str"
}

function isPositiveIntString {
    str=$1
    [[ $str =~ ^[0-9]+$ ]] && return 0 || return 1
}
