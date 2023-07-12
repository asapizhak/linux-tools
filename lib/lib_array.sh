#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

#
#    out_string
#    delimiter
#    $@ - elements
function arrJoinWith { # https://stackoverflow.com/a/17841619
    declare -n out_string=$1
    declare -r delimiter=${2-}
    declare -r first_elem=${3-}

    if shift 3; then
        # shellcheck disable=SC2034
        printf -v out_string %s "$first_elem" "${@/#/$delimiter}"
    fi
}
