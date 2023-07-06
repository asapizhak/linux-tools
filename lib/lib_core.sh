#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################

# Replace $1 with last valid argument number for the function.
# [[ "$1" == "${!#}" ]] && fail "Missing last argument."

function fail {
    msg=${1:-""}
    code=${2:-1}

    [ -n "$msg" ] && echo >&2 "Error: $msg"
    exit $((code))
}

function failWithUsage {
    if [[ $(type -t usage) = 'function' ]]; then
        usage
    fi
    fail "$@"
}

function commandsArePresent {
    cmd_list=("$@")
    suppress_echo=${!#}
    
    if [[ $suppress_echo =~ ^[0-9]+$ ]]; then
        cmd_list=("${cmd_list[@]::${#cmd_list[@]}-1}")
        [[ $suppress_echo -ne 0 ]] && suppress_echo=1
    else suppress_echo=0
    fi

    ret=0
    for cmd in "${cmd_list[@]}"; do
        # if [[ "$arg" -eq 1 ]]; then continue; fi
        if ! command -v "$cmd" >/dev/null 2>&1; then
            [[ $suppress_echo -eq 0 ]] && echo "Command '$cmd' was not found." >&2
            ret=1
        fi
    done
    return $ret
}

function ensureCommands {
    if ! commandsArePresent "$@"; then fail "Missing required commands"; fi
}

function isNameNotTaken {
    name=$1

    if commandsArePresent "$name" 1 || type -t "$name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

function echo2 {
    IFS=' '
    arr=("$@")
    str="${arr[*]}"
    echo  >&2 "$str"
}
