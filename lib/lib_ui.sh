#! /usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

# uiDisplayList array_ref selection_index? title?
function uiDisplayList {
    declare -rn list=$1
    declare -ri selection_idx=${2:--1}
    declare -r title=${3:-}

    [[ -n $title ]] && echo2 "VVV $title VVV";

    for idx in "${!list[@]}"; do
        if [[ $idx -ne -1 && $idx -eq $selection_idx ]]; then
            tput rev
            printf2 "\e[1m%s\e[0m\n" "${list[$idx]}"
            tput sgr0
        else
            printf2 "%s\n" "${list[$idx]}"
        fi
    done
}
