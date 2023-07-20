#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

coreEnsureCommands bc

###############################################################################
# no external command calls here, only pure bash!
# function prefix: num
# Functions that work with numbers here.
###############################################################################

#
#    a
#    b
#    out_result
#    precision=6
function numDivFrac {
    coreEnsureCommands sed
    declare -r a=$1
    declare -r b=$2
    declare -n f_out=$3
    declare -r precision=${4:-6}

    # shellcheck disable=SC2034
    LC_NUMERIC=C printf -v f_out "%f" "$(echo "scale=$precision; $a / $b" | bc)"
    # remove trailing zeroes if there's fractional separator
    f_out="$(sed '/\./ s/\.\{0,1\}0\{1,\}$//' <<< "$f_out")" # https://stackoverflow.com/a/30048933
}

function numCompFrac {
    declare -r a=$1
    declare -r op=$2 # >, >=, <, <=
    declare -r b=$3
    result=$(echo "$a $op $b" | bc -l)
    [[ $result -eq 1 ]] && return 0 || return 1
}

#
#    size_bytes
#    out_size
function numDisplayAsSize {
    coreEnsureCommands sed
    declare size=$1
    declare -n out_size=$2

    declare size_sign=''
    if (( size < 0 )); then size=$(( size * -1 )); size_sign='-'; fi

    declare -a suffixes=("B" "KiB" "MiB" "GiB" "TiB")
    declare suffix=

    for s in "${suffixes[@]}"; do
        if numCompFrac "$size" '>' 1024; then
            numDivFrac "$size" 1024 size 3
        else
            LC_NUMERIC=C printf -v out_size "%f" "$size"
            suffix="$s"
            break
        fi
    done

    if [[ $size_sign == '-' ]]; then out_size="-$out_size"; fi
    # remove trailing zeroes if there's fractional separator
    out_size="$(sed '/\./ s/\.\{0,1\}0\{1,\}$//' <<< "$out_size")$suffix"
}

function numDisplayAsSizeEx {
    declare size=$1
    declare -n out_size_val=$2

    numDisplayAsSize "$size" out_size_val
    printf -v out_size_val "%s (%s bytes)" "$out_size_val" "$size"
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
