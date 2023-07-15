#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################
if [[ ${core__inited:-0} -ne 1 ]]; then
    declare -gir core__inited=1

    # shellcheck disable=SC2034
    declare -ri EXIT_CODE_NO_INPUT_ARGS=55
    # shellcheck disable=SC2034
    declare -ri EXIT_CODE_PREREQUISITE_FAILED=57

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

    declare -ag core_color_names_stack=()
fi

function coreFailExit {
    declare -r msg=${1:-""}
    declare -ri code=$(( "${2:-1}" ))

    [ -n "$msg" ] && echo >&2 "Error: $msg"

    if [[ $code -ne 0 ]]; then
        exit $code
    else
        echo >&2 "Failed to coreFailExit with success code 0"
        exit 1
    fi
}

function coreFailExitWithUsage {
    if [[ $(type -t usage) = 'function' ]]; then
        usage
    fi
    coreFailExit "$@"
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
    if ! commandsArePresent "$@"; then coreFailExit "Missing required commands"; fi
}

function isNameNotTaken {
    declare -r name=$1

    if commandsArePresent 1 "$name" || type -t "$name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Use F_COLOR with color name for colored output
function echo2 {
    declare color_enabled=0

    if declare -p F_COLOR >/dev/null 2>&1 && [[ -n "$F_COLOR" ]]; then
        color_enabled=1
        declare -r color="${COLOR[$F_COLOR]}"
        # shellcheck disable=SC2059
        printf >&2 "$color"
        core_color_names_stack+=("$color")
    fi

    echo >&2 "$@"

    if [[ $color_enabled -eq 1 ]]; then
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            unset 'core_color_names_stack[-1]'
        fi
        declare ret_color_name=default
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            ret_color_name="${core_color_names_stack[-1]}"
        fi
        # shellcheck disable=SC2059
        printf >&2 "${COLOR[$ret_color_name]}"
    fi
}

# Use F_COLOR with color name for colored output
function printf2 {
    declare color_enabled=0

    if declare -p F_COLOR >/dev/null 2>&1 && [[ -n "$F_COLOR" ]]; then
        color_enabled=1
        declare -r color="${COLOR[$F_COLOR]}"
        # shellcheck disable=SC2059
        printf >&2 "$color"
        core_color_names_stack+=("$color")
    fi

    # shellcheck disable=SC2059
    printf >&2 "$@"

    if [[ $color_enabled -eq 1 ]]; then
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            unset 'core_color_names_stack[-1]'
        fi
        declare ret_color_name=default
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            ret_color_name="${core_color_names_stack[-1]}"
        fi
        # shellcheck disable=SC2059
        printf >&2 "${COLOR[$ret_color_name]}"
    fi
}

function trapWithSigname { # https://stackoverflow.com/a/2183063
    declare -r func="$1"
    shift

    # shellcheck disable=SC2317
    function f_proxy {
        declare -r f=$1
        shift

        F_COLOR='cyan' echo2 "┌ Running cleanup ($1)..."
        if "$f" "$@"; then
            F_COLOR='cyan' echo2 "└ Cleanup finished."
        else
            F_COLOR='cyan' echo2 "└ Cleanup failed."
        fi
    }

    for sig; do
        # shellcheck disable=SC2064
        trap "f_proxy $func $sig" "$sig"
    done
}
