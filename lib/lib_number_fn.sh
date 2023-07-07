#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

ensureCommands bc

###############################################################################
# no external command calls here, only pure bash!
# function prefix: num
# Functions that work with numbers here.
###############################################################################

function numDivFrac {
    declare -r a=$1
    declare -r b=$2
    declare -n f_out=$3

    declare -r result=$(echo "scale=6; $a / $b" | bc)
    # shellcheck disable=SC2034
    LC_NUMERIC=C printf -v f_out "%f" "$result"
}

function numCompFrac {
    declare -r a=$1
    declare -r op=$2 # >, >=, <, <=
    declare -r b=$3
    result=$(echo "$a $op $b" | bc -l)
    [[ $result -eq 1 ]] && return 0 || return 1
}

function numDisplayAsSize {
    declare size=$1
    declare -n f_out=$2

    if numCompFrac "$size" '<' 1024; then { printf -v ${!#} "%.3gB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gKiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gMiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    if numCompFrac "$size" '<' 1024; then { LC_NUMERIC=C printf -v ${!#} "%.3gGiB" "$size"; return 0; }; fi
    numDivFrac "$size" 1024 size
    # shellcheck disable=SC2034
    LC_NUMERIC=C printf -v f_out "%.3gTiB" "$size"
}

# numPercentageFrac out_var "what" "of_what" "precision?"=2
function numPercentageFrac {
    declare -n f_out=$1
    declare -r what=$2
    declare -r of_what=$3
    declare -r precision=${4:-2}

    declare -r percent=$(echo "scale=$precision; $what * 100 / $of_what" | bc)
    # shellcheck disable=SC2034
    LC_NUMERIC=C printf -v f_out "%g" "$percent"
}
