#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################
if [[ ${core__inited:-0} -ne 1 ]]; then
    declare -gir core__inited=1

    if declare -p COLOR >/dev/null 2>&1; then
        echo >&2 "Variable 'COLOR' was already defined!"
        exit 1
    fi
    # Color variables
    declare -gA COLOR=()
    COLOR['default']='\033[0m'
    COLOR['red']='\033[0;31m'
    COLOR['green']='\033[0;32m'
    COLOR['yellow']='\033[0;33m'
    COLOR['blue']='\033[0;34m'
    COLOR['magenta']='\033[0;35m'
    COLOR['cyan']='\033[0;36m'
    COLOR['white']='\033[0;37m'
    readonly -A COLOR
fi

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
    else
        suppress_echo=0
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
    declare -r name=$1

    if commandsArePresent 1 "$name" || type -t "$name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

function echo2 {
    echo >&2 "$@"
}

function printf2 {
    # shellcheck disable=SC2059
    printf >&2 "$@"
}

function trapWithSigname { # https://stackoverflow.com/a/2183063
    declare -r func="$1"
    shift
    for sig; do
        # shellcheck disable=SC2064
        trap "$func $sig" "$sig"
    done
}
