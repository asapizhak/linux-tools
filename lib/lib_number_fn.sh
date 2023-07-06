#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# no external command calls here, only pure bash!
# function prefix: num
# Functions that work with numbers here.
###############################################################################

# Replace $1 with last valid argument number for the function.
# [[ "$1" == "${!#}" ]] && fail "Missing last argument."

ensureCommands bc

function numDivFrac {
    a=$1
    b=$2
    [[ "$2" == "${!#}" ]] && fail "Missing last argument."

    result=$(echo "scale=6; $a / $b" | bc)
    LC_NUMERIC=C printf -v ${!#} "%f" "$result"
}

function numCompFrac {
    a=$1
    op=$2 # >, >=, <, <=
    b=$3
    result=$(echo "$a $op $b" | bc -l)
    [[ $result -eq 1 ]] && return 0 || return 1
}

function numDisplayAsSize {
    size=$1
    [[ "$1" == "${!#}" ]] && fail "Missing last argument."

    if numCompFrac "$size" '<' 1024; then { printf -v ${!#} "%.3gB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gKiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gMiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gGiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    LC_NUMERIC=C printf -v ${!#} "%.3gTiB" "$size"
}

function numPercentageFrac {
    what=$1
    of_what=$2
    precision=${3:-2}
    out=$4

    percent=$(echo "scale=$precision; $what * 100 / $of_what" | bc)
    LC_NUMERIC=C printf -v "$out" "%g" "$percent"
}
