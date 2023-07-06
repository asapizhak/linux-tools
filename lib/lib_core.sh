#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################

function fail {
    declare -r msg=${1:-""}
    declare -r code=${2:-1}

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
    declare suppress_echo=$1
    
    if [[ $suppress_echo =~ ^[0-9]+$ ]]; then
        shift
        [[ $suppress_echo -ne 0 ]] && suppress_echo=1
    else suppress_echo=0
    fi

    ret=0
    for cmd in "$@"; do
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

    if commandsArePresent 1 "$name" || type -t "$name" >/dev/null 2>&1; then
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
